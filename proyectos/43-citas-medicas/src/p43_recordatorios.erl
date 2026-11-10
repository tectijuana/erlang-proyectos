-module(p43_recordatorios).
-behaviour(gen_server).

-export([start_link/0, start_link/1, programar/2, cancelar/1, revisar/0,
         estado/1, pendientes/0, ahora/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         handle_continue/2, terminate/2]).

-define(TAB, p43_recordatorios_tab).
-define(MAX_INTENTOS, 3).
-define(REINTENTO_MS, 1000).
-define(MAX_ESPERA_MS, 3600000).
%% Tipo y anticipacion en minutos: 48 h = 2880, 2 h = 120.
-define(ANTICIPOS, [{h48, 2880}, {h2, 120}]).

%%% API ----------------------------------------------------------

start_link() -> start_link(#{}).

%% Opts opcionales: archivo, enviar (fun/2) y reloj (fun/0).
start_link(Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).

%% InicioAbs: momento de la cita en minutos absolutos.
programar(CitaId, InicioAbs) ->
    gen_server:call(?MODULE, {programar, CitaId, InicioAbs}).

cancelar(CitaId)  -> gen_server:call(?MODULE, {cancelar, CitaId}).
revisar()         -> gen_server:call(?MODULE, revisar).
estado(CitaId)    -> gen_server:call(?MODULE, {estado, CitaId}).
pendientes()      -> gen_server:call(?MODULE, pendientes).

%% Reloj por defecto: minutos desde 1970.
ahora() -> erlang:system_time(second) div 60.

%%% Callbacks ----------------------------------------------------

init(Opts) ->
    process_flag(trap_exit, true),
    Archivo = maps:get(archivo, Opts, archivo_por_defecto()),
    {ok, ?TAB} = dets:open_file(?TAB, [{file, Archivo}, {type, set}]),
    State = #{enviar => maps:get(enviar, Opts, fun enviar_por_defecto/2),
              reloj => maps:get(reloj, Opts, fun ahora/0),
              timer => undefined},
    %% Lo que vencio mientras estuvimos caidos sale en cuanto arranca.
    {ok, State, {continue, revisar}}.

handle_continue(revisar, State) ->
    {noreply, procesar(State)}.

handle_call({programar, CitaId, InicioAbs}, _From,
            #{reloj := Reloj} = State) when is_integer(InicioAbs) ->
    Ahora = Reloj(),
    %% Si el recordatorio ya paso (cita agendada con poca anticipacion)
    %% no se programa. insert_new evita duplicar si se llama dos veces.
    Nuevos = [dets:insert_new(?TAB, {{CitaId, Tipo}, CitaId, Tipo,
                                     InicioAbs - Antes, pendiente, 0})
              || {Tipo, Antes} <- ?ANTICIPOS, InicioAbs - Antes >= Ahora],
    dets:sync(?TAB),
    {reply, {ok, length([ok || true <- Nuevos])}, reprogramar(State)};
handle_call({programar, _CitaId, _InicioAbs}, _From, State) ->
    {reply, {error, momento_invalido}, State};
handle_call({cancelar, CitaId}, _From, State) ->
    [dets:delete(?TAB, {CitaId, Tipo}) || {Tipo, _} <- ?ANTICIPOS],
    dets:sync(?TAB),
    {reply, ok, reprogramar(State)};
handle_call(revisar, _From, State) ->
    {reply, ok, procesar(State)};
handle_call({estado, CitaId}, _From, State) ->
    Filas = dets:match_object(?TAB, {{CitaId, '_'}, CitaId, '_', '_', '_', '_'}),
    {reply, lists:sort([{Tipo, Estado} || {_, _, Tipo, _, Estado, _} <- Filas]),
     State};
handle_call(pendientes, _From, State) ->
    {reply, lists:sort([{C, T, M} || {_, C, T, M, _, _} <- pendientes_tab()]),
     State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(revisar, State) ->
    {noreply, procesar(State#{timer := undefined})};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Razon, _State) ->
    dets:close(?TAB),
    ok.

%%% Internas -----------------------------------------------------

archivo_por_defecto() ->
    application:get_env(p43_citas_medicas, recordatorios_archivo,
                        "p43_recordatorios.dets").

enviar_por_defecto(CitaId, Tipo) ->
    logger:notice("recordatorio ~p para la cita ~p", [Tipo, CitaId]),
    ok.

pendientes_tab() ->
    dets:match_object(?TAB, {'_', '_', '_', '_', pendiente, '_'}).

%% Envia todo lo vencido y reprograma el timer.
procesar(#{reloj := Reloj, enviar := Enviar} = State) ->
    Ahora = Reloj(),
    Vencidos = [F || {_, _, _, Momento, _, _} = F <- pendientes_tab(),
                     Momento =< Ahora],
    lists:foreach(fun(F) -> entregar(F, Enviar) end, Vencidos),
    dets:sync(?TAB),
    reprogramar(State).

%% Una excepcion en el envio no tumba al proceso: cuenta como fallo.
entregar({Clave, CitaId, Tipo, Momento, _Estado, Intentos}, Enviar) ->
    Resultado = try Enviar(CitaId, Tipo)
                catch Clase:Razon -> {error, {Clase, Razon}}
                end,
    case Resultado of
        ok ->
            dets:insert(?TAB, {Clave, CitaId, Tipo, Momento, enviado, Intentos});
        Otro ->
            N = Intentos + 1,
            Estado = case N >= ?MAX_INTENTOS of
                         true  -> fallido;
                         false -> pendiente
                     end,
            logger:warning("recordatorio ~p de ~p fallo (~p), intento ~p, ~p",
                           [Tipo, CitaId, Otro, N, Estado]),
            dets:insert(?TAB, {Clave, CitaId, Tipo, Momento, Estado, N})
    end.

%% Un solo timer, apuntando al proximo vencimiento.
reprogramar(#{timer := Timer, reloj := Reloj} = State) ->
    cancelar_timer(Timer),
    case pendientes_tab() of
        [] ->
            State#{timer := undefined};
        Filas ->
            Ahora = Reloj(),
            Proximo = lists:min([M || {_, _, _, M, _, _} <- Filas]),
            Espera = case Proximo =< Ahora of
                         true  -> ?REINTENTO_MS;   % vencido: es un reintento
                         false -> min((Proximo - Ahora) * 60000, ?MAX_ESPERA_MS)
                     end,
            State#{timer := erlang:send_after(Espera, self(), revisar)}
    end.

cancelar_timer(undefined) -> ok;
cancelar_timer(Timer)     -> erlang:cancel_timer(Timer), ok.

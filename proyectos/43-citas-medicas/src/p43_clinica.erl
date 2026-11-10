-module(p43_clinica).
-behaviour(gen_server).

-export([start_link/0, medicos/0, agendar/6, confirmar/1, atender/1,
         cancelar/1, no_show/1, cita/1, citas/0, agenda/1, agenda/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         handle_continue/2]).

-define(TAB, p43_citas_tab).
-define(MEDICOS, lists:seq(1, 10)).

%%% API ----------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

medicos() -> ?MEDICOS.

%% Fecha = {Anio, Mes, Dia}; Ini y Fin en minutos del dia.
agendar(CitaId, Paciente, Medico, Fecha, Ini, Fin) ->
    gen_server:call(?MODULE,
                    {agendar, CitaId, Paciente, Medico, Fecha, Ini, Fin}).

confirmar(CitaId) -> gen_server:call(?MODULE, {transicion, CitaId, confirmar}).
atender(CitaId)   -> gen_server:call(?MODULE, {transicion, CitaId, atender}).
cancelar(CitaId)  -> gen_server:call(?MODULE, {transicion, CitaId, cancelar}).
no_show(CitaId)   -> gen_server:call(?MODULE, {transicion, CitaId, no_show}).

%% Lecturas directo a ETS.
cita(CitaId) ->
    case ets:lookup(?TAB, CitaId) of
        [{CitaId, Pid, _Medico}] -> {ok, p43_cita:info(Pid)};
        [] -> {error, no_existe}
    end.

citas() -> [Id || {Id, _, _} <- lists:sort(ets:tab2list(?TAB))].

%% Toda la agenda del medico: [{Dia, Ini, Fin, CitaId}].
agenda(Medico) ->
    case ets:lookup(p43_medicos_tab, Medico) of
        [{Medico, Pid}] -> {ok, p43_medico:agenda(Pid)};
        [] -> {error, medico_no_existe}
    end.

%% Agenda de un dia concreto: [{Ini, Fin, CitaId}].
agenda(Medico, Fecha) ->
    case {ets:lookup(p43_medicos_tab, Medico), dia_de(Fecha)} of
        {[], _}                 -> {error, medico_no_existe};
        {_, error}              -> {error, fecha_invalida};
        {[{Medico, Pid}], {ok, Dia}} -> {ok, p43_medico:agenda(Pid, Dia)}
    end.

%%% Callbacks ----------------------------------------------------

init([]) ->
    ets:new(?TAB, [named_table, protected, set, {read_concurrency, true}]),
    ets:new(p43_medicos_tab, [named_table, protected, set]),
    {ok, #{refs => #{}}, {continue, sembrar_medicos}}.

handle_continue(sembrar_medicos, State) ->
    [begin
         {ok, Pid} = p43_medicos_sup:start_medico(M),
         ets:insert(p43_medicos_tab, {M, Pid})
     end || M <- ?MEDICOS],
    {noreply, State}.

handle_call({agendar, CitaId, Paciente, Medico, Fecha, Ini, Fin}, _From, State) ->
    case dia_de(Fecha) of
        error ->
            {reply, {error, fecha_invalida}, State};
        {ok, Dia} ->
            agendar_valido(CitaId, Paciente, Medico, Fecha, Dia, Ini, Fin, State)
    end;
handle_call({transicion, CitaId, Accion}, _From, State) ->
    case ets:lookup(?TAB, CitaId) of
        [] ->
            {reply, {error, no_existe}, State};
        [{CitaId, CPid, Medico}] ->
            Resp = p43_cita:Accion(CPid),
            despues_de(Resp, Accion, CitaId, Medico),
            {reply, Resp, State}
    end.

handle_cast(_Msg, State) ->
    {noreply, State}.

%% Una cita murio de forma inesperada: se libera su hueco, se
%% cancelan sus recordatorios y se quita del registro.
handle_info({'DOWN', Ref, process, _Pid, Razon}, #{refs := Refs} = State) ->
    case maps:take(Ref, Refs) of
        {CitaId, Refs1} ->
            case ets:lookup(?TAB, CitaId) of
                [{CitaId, _, Medico}] ->
                    logger:warning("cita ~p caida (~p), se libera su hueco",
                                   [CitaId, Razon]),
                    liberar(CitaId, Medico),
                    quitar_recordatorios(CitaId),
                    ets:delete(?TAB, CitaId);
                [] -> ok
            end,
            {noreply, State#{refs := Refs1}};
        error ->
            {noreply, State}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

%%% Internas -----------------------------------------------------

agendar_valido(CitaId, Paciente, Medico, Fecha, Dia, Ini, Fin,
               #{refs := Refs} = State) ->
    case {ets:lookup(?TAB, CitaId), ets:lookup(p43_medicos_tab, Medico)} of
        {[_], _} ->
            {reply, {error, cita_duplicada}, State};
        {_, []} ->
            {reply, {error, medico_no_existe}, State};
        {[], [{Medico, MPid}]} ->
            case p43_medico:reservar(MPid, CitaId, Dia, Ini, Fin) of
                ok ->
                    Datos = #{id => CitaId, paciente => Paciente,
                              medico => Medico, fecha => Fecha,
                              inicio => Ini, fin => Fin},
                    {ok, CPid} = p43_citas_sup:start_cita(Datos),
                    ets:insert(?TAB, {CitaId, CPid, Medico}),
                    Ref = erlang:monitor(process, CPid),
                    programar_recordatorios(CitaId, momento_abs(Dia, Ini)),
                    {reply, ok, State#{refs := Refs#{Ref => CitaId}}};
                {error, _} = Error ->
                    {reply, Error, State}
            end
    end.

%% {Y,M,D} valido -> {ok, DiaGregoriano}; cualquier otra cosa -> error.
dia_de({Y, M, D}) when is_integer(Y), is_integer(M), is_integer(D), Y >= 1970 ->
    case calendar:valid_date(Y, M, D) of
        true  -> {ok, calendar:date_to_gregorian_days(Y, M, D)};
        false -> error
    end;
dia_de(_) ->
    error.

%% Minutos desde 1970, la misma escala del reloj de recordatorios.
momento_abs(Dia, Ini) ->
    (Dia - calendar:date_to_gregorian_days(1970, 1, 1)) * 1440 + Ini.

%% Cancelar y no_show liberan el hueco. Cancelar, no_show y atender
%% dejan sin sentido los recordatorios pendientes.
despues_de(ok, Accion, CitaId, Medico)
  when Accion =:= cancelar; Accion =:= no_show ->
    liberar(CitaId, Medico),
    quitar_recordatorios(CitaId);
despues_de(ok, atender, CitaId, _Medico) ->
    quitar_recordatorios(CitaId);
despues_de(_, _, _, _) ->
    ok.

liberar(CitaId, Medico) ->
    case ets:lookup(p43_medicos_tab, Medico) of
        [{Medico, MPid}] -> p43_medico:cancelar(MPid, CitaId);
        [] -> ok
    end.

%% Si el servicio de recordatorios no responde, la cita igual se agenda:
%% se registra el problema en el log en vez de tumbar a la clinica.
programar_recordatorios(CitaId, Abs) ->
    try p43_recordatorios:programar(CitaId, Abs)
    catch exit:Razon ->
        logger:error("no se pudo programar recordatorio de ~p: ~p",
                     [CitaId, Razon])
    end.

quitar_recordatorios(CitaId) ->
    try p43_recordatorios:cancelar(CitaId)
    catch exit:Razon ->
        logger:error("no se pudo cancelar recordatorio de ~p: ~p",
                     [CitaId, Razon])
    end.

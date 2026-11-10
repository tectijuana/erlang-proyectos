-module(p43_clinica).
-behaviour(gen_server).

-export([start_link/0, medicos/0, agendar/5, confirmar/1, atender/1,
         cancelar/1, no_show/1, cita/1, citas/0, agenda/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         handle_continue/2]).

-define(TAB, p43_citas_tab).
-define(MEDICOS, lists:seq(1, 10)).

%%% API ----------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

medicos() -> ?MEDICOS.

agendar(CitaId, Paciente, Medico, Ini, Fin) ->
    gen_server:call(?MODULE, {agendar, CitaId, Paciente, Medico, Ini, Fin}).

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

agenda(Medico) ->
    case ets:lookup(p43_medicos_tab, Medico) of
        [{Medico, Pid}] -> {ok, p43_medico:agenda(Pid)};
        [] -> {error, medico_no_existe}
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

handle_call({agendar, CitaId, Paciente, Medico, Ini, Fin}, _From,
            #{refs := Refs} = State) ->
    case {ets:lookup(?TAB, CitaId), ets:lookup(p43_medicos_tab, Medico)} of
        {[_], _} ->
            {reply, {error, cita_duplicada}, State};
        {_, []} ->
            {reply, {error, medico_no_existe}, State};
        {[], [{Medico, MPid}]} ->
            case p43_medico:reservar(MPid, CitaId, Ini, Fin) of
                ok ->
                    Datos = #{id => CitaId, paciente => Paciente,
                              medico => Medico, inicio => Ini, fin => Fin},
                    {ok, CPid} = p43_citas_sup:start_cita(Datos),
                    ets:insert(?TAB, {CitaId, CPid, Medico}),
                    Ref = erlang:monitor(process, CPid),
                    {reply, ok, State#{refs := Refs#{Ref => CitaId}}};
                {error, _} = Error ->
                    {reply, Error, State}
            end
    end;
handle_call({transicion, CitaId, Accion}, _From, State) ->
    case ets:lookup(?TAB, CitaId) of
        [] ->
            {reply, {error, no_existe}, State};
        [{CitaId, CPid, Medico}] ->
            Resp = p43_cita:Accion(CPid),
            liberar_si_corresponde(Resp, Accion, CitaId, Medico),
            {reply, Resp, State}
    end.

handle_cast(_Msg, State) ->
    {noreply, State}.

%% Una cita murio de forma inesperada: se libera su hueco y se
%% quita del registro, para que no quede una agenda fantasma.
handle_info({'DOWN', Ref, process, _Pid, Razon}, #{refs := Refs} = State) ->
    case maps:take(Ref, Refs) of
        {CitaId, Refs1} ->
            case ets:lookup(?TAB, CitaId) of
                [{CitaId, _, Medico}] ->
                    logger:warning("cita ~p caida (~p), se libera su hueco",
                                   [CitaId, Razon]),
                    liberar(CitaId, Medico),
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

%% Cancelar o no_show exitosos liberan el hueco del medico.
liberar_si_corresponde(ok, Accion, CitaId, Medico)
  when Accion =:= cancelar; Accion =:= no_show ->
    liberar(CitaId, Medico);
liberar_si_corresponde(_, _, _, _) ->
    ok.

liberar(CitaId, Medico) ->
    case ets:lookup(p43_medicos_tab, Medico) of
        [{Medico, MPid}] -> p43_medico:cancelar(MPid, CitaId);
        [] -> ok
    end.

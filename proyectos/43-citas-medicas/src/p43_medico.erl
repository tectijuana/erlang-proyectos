-module(p43_medico).
-behaviour(gen_server).

-export([start_link/1, reservar/4, cancelar/2, agenda/1]).
-export([init/1, handle_call/3, handle_cast/2]).

%%% API ----------------------------------------------------------

start_link(MedicoId) ->
    gen_server:start_link(?MODULE, MedicoId, []).

%% Ini y Fin son minutos desde medianoche. El intervalo es [Ini, Fin).
reservar(Medico, CitaId, Ini, Fin) ->
    gen_server:call(Medico, {reservar, CitaId, Ini, Fin}).

cancelar(Medico, CitaId) -> gen_server:call(Medico, {cancelar, CitaId}).
agenda(Medico)           -> gen_server:call(Medico, agenda).

%%% Callbacks ----------------------------------------------------

%% La agenda es una lista de {Ini, Fin, CitaId} ordenada por Ini.
init(MedicoId) ->
    {ok, #{medico => MedicoId, agenda => []}}.

handle_call({reservar, CitaId, Ini, Fin}, _From, #{agenda := Agenda} = State)
  when is_integer(Ini), is_integer(Fin), Ini < Fin ->
    case lists:any(fun({I, F, _}) -> Ini < F andalso I < Fin end, Agenda) of
        true ->
            {reply, {error, horario_ocupado}, State};
        false ->
            Nueva = lists:keysort(1, [{Ini, Fin, CitaId} | Agenda]),
            {reply, ok, State#{agenda := Nueva}}
    end;
handle_call({reservar, _CitaId, _Ini, _Fin}, _From, State) ->
    {reply, {error, intervalo_invalido}, State};
handle_call({cancelar, CitaId}, _From, #{agenda := Agenda} = State) ->
    case lists:keytake(CitaId, 3, Agenda) of
        {value, _, Resto} -> {reply, ok, State#{agenda := Resto}};
        false             -> {reply, {error, no_existe}, State}
    end;
handle_call(agenda, _From, #{agenda := Agenda} = State) ->
    {reply, Agenda, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

-module(p43_medico).
-behaviour(gen_server).

-export([start_link/1, reservar/5, cancelar/2, agenda/1, agenda/2]).
-export([init/1, handle_call/3, handle_cast/2]).

%%% API ----------------------------------------------------------

start_link(MedicoId) ->
    gen_server:start_link(?MODULE, MedicoId, []).

%% Dia: entero (dias gregorianos). Ini y Fin: minutos del dia,
%% el intervalo es [Ini, Fin).
reservar(Medico, CitaId, Dia, Ini, Fin) ->
    gen_server:call(Medico, {reservar, CitaId, Dia, Ini, Fin}).

cancelar(Medico, CitaId) -> gen_server:call(Medico, {cancelar, CitaId}).

%% Toda la agenda: [{Dia, Ini, Fin, CitaId}] ordenada.
agenda(Medico)      -> gen_server:call(Medico, agenda).
%% Solo un dia: [{Ini, Fin, CitaId}].
agenda(Medico, Dia) -> gen_server:call(Medico, {agenda, Dia}).

%%% Callbacks ----------------------------------------------------

init(MedicoId) ->
    {ok, #{medico => MedicoId, agenda => []}}.

handle_call({reservar, CitaId, Dia, Ini, Fin}, _From, #{agenda := Agenda} = State)
  when is_integer(Dia), is_integer(Ini), is_integer(Fin),
       Ini >= 0, Ini < Fin, Fin =< 1440 ->
    Traslape = lists:any(fun({D, I, F, _}) ->
                                 D =:= Dia andalso Ini < F andalso I < Fin
                         end, Agenda),
    case Traslape of
        true ->
            {reply, {error, horario_ocupado}, State};
        false ->
            Nueva = lists:sort([{Dia, Ini, Fin, CitaId} | Agenda]),
            {reply, ok, State#{agenda := Nueva}}
    end;
handle_call({reservar, _, _, _, _}, _From, State) ->
    {reply, {error, intervalo_invalido}, State};
handle_call({cancelar, CitaId}, _From, #{agenda := Agenda} = State) ->
    case lists:keytake(CitaId, 4, Agenda) of
        {value, _, Resto} -> {reply, ok, State#{agenda := Resto}};
        false             -> {reply, {error, no_existe}, State}
    end;
handle_call(agenda, _From, #{agenda := Agenda} = State) ->
    {reply, Agenda, State};
handle_call({agenda, Dia}, _From, #{agenda := Agenda} = State) ->
    {reply, [{I, F, C} || {D, I, F, C} <- Agenda, D =:= Dia], State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

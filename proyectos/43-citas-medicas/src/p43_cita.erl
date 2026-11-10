-module(p43_cita).
-behaviour(gen_statem).

-export([start_link/1, confirmar/1, atender/1, cancelar/1, no_show/1, info/1]).
-export([init/1, callback_mode/0]).
-export([agendada/3, confirmada/3, atendida/3, cancelada/3, no_show/3]).

%%% API ----------------------------------------------------------

%% Datos = #{id, paciente, medico, inicio, fin}
start_link(Datos) ->
    gen_statem:start_link(?MODULE, Datos, []).

confirmar(Cita) -> gen_statem:call(Cita, confirmar).
atender(Cita)   -> gen_statem:call(Cita, atender).
cancelar(Cita)  -> gen_statem:call(Cita, cancelar).
no_show(Cita)   -> gen_statem:call(Cita, no_show).
info(Cita)      -> gen_statem:call(Cita, info).

%%% Callbacks ----------------------------------------------------

callback_mode() -> state_functions.

init(Datos) ->
    {ok, agendada, Datos}.

%%% Estados ------------------------------------------------------

agendada({call, From}, confirmar, D) ->
    {next_state, confirmada, D, [{reply, From, ok}]};
agendada({call, From}, cancelar, D) ->
    {next_state, cancelada, D, [{reply, From, ok}]};
agendada({call, From}, no_show, D) ->
    {next_state, no_show, D, [{reply, From, ok}]};
agendada(Tipo, Evento, D) ->
    comun(Tipo, Evento, agendada, D).

confirmada({call, From}, atender, D) ->
    {next_state, atendida, D, [{reply, From, ok}]};
confirmada({call, From}, cancelar, D) ->
    {next_state, cancelada, D, [{reply, From, ok}]};
confirmada({call, From}, no_show, D) ->
    {next_state, no_show, D, [{reply, From, ok}]};
confirmada(Tipo, Evento, D) ->
    comun(Tipo, Evento, confirmada, D).

%% Estados finales: solo aceptan consultas.
atendida(Tipo, Evento, D)  -> comun(Tipo, Evento, atendida, D).
cancelada(Tipo, Evento, D) -> comun(Tipo, Evento, cancelada, D).
no_show(Tipo, Evento, D)   -> comun(Tipo, Evento, no_show, D).

%%% Eventos comunes ----------------------------------------------

%% info devuelve los datos de la cita mas su estado actual.
comun({call, From}, info, Estado, D) ->
    {keep_state, D, [{reply, From, D#{estado => Estado}}]};
comun({call, From}, _Evento, Estado, D) ->
    {keep_state, D, [{reply, From, {error, {transicion_invalida, Estado}}}]};
comun(_Tipo, _Evento, _Estado, D) ->
    {keep_state, D}.

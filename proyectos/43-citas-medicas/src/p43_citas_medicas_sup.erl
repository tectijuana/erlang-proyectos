-module(p43_citas_medicas_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% rest_for_one: la clinica depende de los dos supervisores de
%% arriba. Si cae uno de ellos, la clinica se reinicia y vuelve a
%% sembrar a los medicos.
init([]) ->
    Children = [
        #{id => p43_citas_sup,
          start => {p43_citas_sup, start_link, []},
          restart => permanent, shutdown => infinity, type => supervisor},
        #{id => p43_medicos_sup,
          start => {p43_medicos_sup, start_link, []},
          restart => permanent, shutdown => infinity, type => supervisor},
        #{id => p43_clinica,
          start => {p43_clinica, start_link, []},
          restart => permanent, shutdown => 5000, type => worker}
    ],
    {ok, {#{strategy => rest_for_one, intensity => 10, period => 60},
          Children}}.

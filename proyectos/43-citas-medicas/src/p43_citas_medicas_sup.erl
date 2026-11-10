-module(p43_citas_medicas_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% rest_for_one: lo que viene despues depende de lo anterior.
%% Si cae un supervisor o los recordatorios, la clinica se reinicia
%% y vuelve a sembrar a los medicos. Los recordatorios sobreviven
%% porque viven en disco (DETS).
init([]) ->
    Children = [
        #{id => p43_citas_sup,
          start => {p43_citas_sup, start_link, []},
          restart => permanent, shutdown => infinity, type => supervisor},
        #{id => p43_medicos_sup,
          start => {p43_medicos_sup, start_link, []},
          restart => permanent, shutdown => infinity, type => supervisor},
        #{id => p43_recordatorios,
          start => {p43_recordatorios, start_link, []},
          restart => permanent, shutdown => 5000, type => worker},
        #{id => p43_clinica,
          start => {p43_clinica, start_link, []},
          restart => permanent, shutdown => 5000, type => worker}
    ],
    {ok, {#{strategy => rest_for_one, intensity => 10, period => 60},
          Children}}.

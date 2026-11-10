-module(p43_medicos_sup).
-behaviour(supervisor).

-export([start_link/0, start_medico/1]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_medico(MedicoId) ->
    supervisor:start_child(?MODULE, [MedicoId]).

init([]) ->
    Hijo = #{id => p43_medico,
             start => {p43_medico, start_link, []},
             restart => permanent,
             shutdown => 5000,
             type => worker},
    {ok, {#{strategy => simple_one_for_one, intensity => 10, period => 60},
          [Hijo]}}.

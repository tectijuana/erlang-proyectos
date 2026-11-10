-module(p43_citas_sup).
-behaviour(supervisor).

-export([start_link/0, start_cita/1]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_cita(Datos) ->
    supervisor:start_child(?MODULE, [Datos]).

%% temporary: una cita que muere no se reinicia sola (volveria a
%% 'agendada' y mentiria). La clinica se entera por su monitor.
init([]) ->
    Hijo = #{id => p43_cita,
             start => {p43_cita, start_link, []},
             restart => temporary,
             shutdown => 5000,
             type => worker},
    {ok, {#{strategy => simple_one_for_one, intensity => 10, period => 60},
          [Hijo]}}.

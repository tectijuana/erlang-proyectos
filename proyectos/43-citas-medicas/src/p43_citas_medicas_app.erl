-module(p43_citas_medicas_app).
-behaviour(application).

-export([start/2, stop/1]).

%% Arranca el arbol de supervision y despues la API HTTP.
%% El puerto sale de sys.config (http_port); por defecto 8080.
start(_StartType, _StartArgs) ->
  case p43_citas_medicas_sup:start_link() of
    {ok, Sup} ->
      Puerto = application:get_env(p43_citas_medicas, http_port, 8080),
      {ok, _} = p43_http:start(Puerto),
      {ok, Sup};
    Error ->
      Error
  end.

stop(_State) ->
  p43_http:stop(),
  ok.

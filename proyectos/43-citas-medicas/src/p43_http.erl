-module(p43_http).

-export([start/0, start/1, stop/0]).

-define(LISTENER, p43_http_listener).

start() -> start(8080).

start(Puerto) ->
    {ok, _} = application:ensure_all_started(cowboy),
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/medicos", p43_http_handler, medicos},
            {"/medicos/:id/agenda", p43_http_handler, agenda},
            {"/citas", p43_http_handler, citas},
            {"/citas/:id", p43_http_handler, cita},
            {"/citas/:id/:accion", p43_http_handler, accion}
        ]}
    ]),
    cowboy:start_clear(?LISTENER, [{port, Puerto}],
                       #{env => #{dispatch => Dispatch}}).

stop() -> cowboy:stop_listener(?LISTENER).

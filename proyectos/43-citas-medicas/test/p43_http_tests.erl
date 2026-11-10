-module(p43_http_tests).
-include_lib("eunit/include/eunit.hrl").

-define(PUERTO, 18080).
-define(BASE, "http://127.0.0.1:18080").

http_test_() ->
    {foreach,
     fun() ->
             Archivo = "/tmp/p43_http_" ++
                       integer_to_list(erlang:unique_integer([positive])) ++ ".dets",
             application:set_env(p43_citas_medicas, recordatorios_archivo, Archivo),
             {ok, _} = application:ensure_all_started(inets),
             {ok, Sup} = p43_citas_medicas_sup:start_link(),
             unlink(Sup),
             timer:sleep(100),
             {ok, _} = p43_http:start(?PUERTO),
             {Sup, Archivo}
     end,
     fun({Sup, Archivo}) ->
             p43_http:stop(),
             exit(Sup, shutdown),
             timer:sleep(100),
             file:delete(Archivo)
     end,
     [fun(_) -> ?_test(crear_y_consultar()) end,
      fun(_) -> ?_test(traslape_da_409()) end,
      fun(_) -> ?_test(campo_invalido_da_400()) end,
      fun(_) -> ?_test(fecha_invalida_da_422()) end,
      fun(_) -> ?_test(flujo_confirmar_atender()) end,
      fun(_) -> ?_test(cancelar_libera_hueco()) end,
      fun(_) -> ?_test(agenda_de_un_dia()) end,
      fun(_) -> ?_test(inexistentes_dan_404()) end]}.

crear_y_consultar() ->
    {201, R} = pedir(post, "/citas", cuerpo(1, 1, <<"2030-01-15">>, <<"09:00">>, <<"09:30">>)),
    ?assertEqual(<<"agendada">>, maps:get(<<"estado">>, R)),
    ?assertEqual(<<"09:00">>, maps:get(<<"inicio">>, R)),
    {200, R2} = pedir(get, "/citas/1"),
    ?assertEqual(<<"2030-01-15">>, maps:get(<<"fecha">>, R2)),
    ?assertEqual(<<"09:30">>, maps:get(<<"fin">>, R2)).

%% Una cita con minutos y la otra con "HH:MM": prueba ambos formatos.
traslape_da_409() ->
    {201, _} = pedir(post, "/citas", cuerpo(1, 1, <<"2030-01-15">>, 540, 570)),
    {409, R} = pedir(post, "/citas", cuerpo(2, 1, <<"2030-01-15">>, <<"09:15">>, <<"09:45">>)),
    ?assertEqual(<<"horario_ocupado">>, maps:get(<<"error">>, R)),
    {404, _} = pedir(get, "/citas/2").

campo_invalido_da_400() ->
    Sin = maps:remove(<<"paciente">>,
                      cuerpo(1, 1, <<"2030-01-15">>, 540, 570)),
    {400, R} = pedir(post, "/citas", Sin),
    ?assertEqual(<<"campo_invalido">>, maps:get(<<"error">>, R)),
    ?assertEqual(<<"paciente">>, maps:get(<<"campo">>, R)).

fecha_invalida_da_422() ->
    {422, R} = pedir(post, "/citas", cuerpo(1, 1, <<"2030-02-30">>, 540, 570)),
    ?assertEqual(<<"fecha_invalida">>, maps:get(<<"error">>, R)).

flujo_confirmar_atender() ->
    {201, _} = pedir(post, "/citas", cuerpo(1, 1, <<"2030-01-15">>, 540, 570)),
    {200, _} = pedir(post, "/citas/1/confirmar", #{}),
    {200, R} = pedir(post, "/citas/1/atender", #{}),
    ?assertEqual(<<"atendida">>, maps:get(<<"estado">>, R)).

cancelar_libera_hueco() ->
    {201, _} = pedir(post, "/citas", cuerpo(1, 1, <<"2030-01-15">>, 540, 570)),
    {200, R} = pedir(post, "/citas/1/cancelar", #{}),
    ?assertEqual(<<"cancelada">>, maps:get(<<"estado">>, R)),
    {200, A} = pedir(get, "/medicos/1/agenda?fecha=2030-01-15"),
    ?assertEqual([], maps:get(<<"citas">>, A)),
    {201, _} = pedir(post, "/citas", cuerpo(2, 1, <<"2030-01-15">>, 540, 570)).

agenda_de_un_dia() ->
    {201, _} = pedir(post, "/citas", cuerpo(1, 1, <<"2030-01-15">>, 540, 570)),
    {201, _} = pedir(post, "/citas", cuerpo(2, 1, <<"2030-01-16">>, 600, 630)),
    {200, A} = pedir(get, "/medicos/1/agenda?fecha=2030-01-16"),
    [Cita] = maps:get(<<"citas">>, A),
    ?assertEqual(2, maps:get(<<"id">>, Cita)),
    ?assertEqual(<<"10:00">>, maps:get(<<"inicio">>, Cita)),
    {200, Toda} = pedir(get, "/medicos/1/agenda"),
    ?assertEqual(2, length(maps:get(<<"citas">>, Toda))).

inexistentes_dan_404() ->
    {404, _} = pedir(get, "/citas/999"),
    {404, _} = pedir(post, "/citas/999/cancelar", #{}),
    {404, _} = pedir(get, "/medicos/99/agenda"),
    {404, _} = pedir(post, "/citas/1/borrar", #{}).

%%% Auxiliares ---------------------------------------------------

cuerpo(Id, Medico, Fecha, Ini, Fin) ->
    #{<<"id">> => Id, <<"paciente">> => <<"Ana">>, <<"medico">> => Medico,
      <<"fecha">> => Fecha, <<"inicio">> => Ini, <<"fin">> => Fin}.

pedir(get, Ruta) ->
    {ok, {{_, Codigo, _}, _, Resp}} =
        httpc:request(get, {?BASE ++ Ruta, []}, [], [{body_format, binary}]),
    {Codigo, json:decode(Resp)}.

pedir(post, Ruta, Mapa) ->
    Cuerpo = iolist_to_binary(json:encode(Mapa)),
    {ok, {{_, Codigo, _}, _, Resp}} =
        httpc:request(post, {?BASE ++ Ruta, [], "application/json", Cuerpo},
                      [], [{body_format, binary}]),
    {Codigo, json:decode(Resp)}.

-module(p43_recordatorios_tests).
-include_lib("eunit/include/eunit.hrl").

%% Cita en el minuto absoluto 10000: h48 vence en 7120, h2 en 9880.

recordatorios_test_() ->
    {foreach,
     fun() ->
             Archivo = "/tmp/p43_rec_" ++
                       integer_to_list(erlang:unique_integer([positive])) ++ ".dets",
             A = atomics:new(1, [{signed, true}]),
             {Archivo, A}
     end,
     fun({Archivo, _A}) ->
             detener(),
             file:delete(Archivo)
     end,
     [fun(C) -> ?_test(programa_dos(C)) end,
      fun(C) -> ?_test(sale_en_su_momento(C)) end,
      fun(C) -> ?_test(no_programa_lo_que_ya_paso(C)) end,
      fun(C) -> ?_test(sobrevive_a_reinicio(C)) end,
      fun(C) -> ?_test(sobrevive_a_kill(C)) end,
      fun(C) -> ?_test(falla_se_reintenta_y_se_marca(C)) end,
      fun(C) -> ?_test(excepcion_no_tumba_el_proceso(C)) end,
      fun(C) -> ?_test(cancelar_borra_los_pendientes(C)) end]}.

%%% Auxiliares ---------------------------------------------------

arrancar(Archivo, A, Enviar) ->
    {ok, Pid} = p43_recordatorios:start_link(
                  #{archivo => Archivo,
                    reloj => fun() -> atomics:get(A, 1) end,
                    enviar => Enviar}),
    unlink(Pid),
    Pid.

detener() ->
    case whereis(p43_recordatorios) of
        undefined -> ok;
        Pid -> gen_server:stop(Pid)
    end.

enviador(Padre) ->
    fun(Cita, Tipo) -> Padre ! {enviado, Cita, Tipo}, ok end.

recibir(0) -> [];
recibir(N) ->
    receive {enviado, C, T} -> [{C, T} | recibir(N - 1)]
    after 500 -> [timeout]
    end.

nada_mas() ->
    receive {enviado, _, _} = M -> {algo, M}
    after 50 -> nada
    end.

%%% Pruebas ------------------------------------------------------

programa_dos({Archivo, A}) ->
    atomics:put(A, 1, 0),
    arrancar(Archivo, A, enviador(self())),
    ?assertEqual({ok, 2}, p43_recordatorios:programar(c1, 10000)),
    ?assertEqual([{h2, pendiente}, {h48, pendiente}],
                 p43_recordatorios:estado(c1)).

sale_en_su_momento({Archivo, A}) ->
    atomics:put(A, 1, 0),
    arrancar(Archivo, A, enviador(self())),
    {ok, 2} = p43_recordatorios:programar(c1, 10000),
    atomics:put(A, 1, 7120),
    ok = p43_recordatorios:revisar(),
    ?assertEqual([{c1, h48}], recibir(1)),
    ?assertEqual(nada, nada_mas()),
    ?assertEqual([{h2, pendiente}, {h48, enviado}], p43_recordatorios:estado(c1)),
    atomics:put(A, 1, 9880),
    ok = p43_recordatorios:revisar(),
    ?assertEqual([{c1, h2}], recibir(1)),
    ?assertEqual([{h2, enviado}, {h48, enviado}], p43_recordatorios:estado(c1)).

no_programa_lo_que_ya_paso({Archivo, A}) ->
    atomics:put(A, 1, 9000),
    arrancar(Archivo, A, enviador(self())),
    %% Faltan menos de 48 h: solo tiene sentido el de 2 h.
    ?assertEqual({ok, 1}, p43_recordatorios:programar(c1, 10000)),
    ?assertEqual([{h2, pendiente}], p43_recordatorios:estado(c1)).

%% Detener el proceso y arrancarlo de nuevo: lo vencido sale de inmediato.
sobrevive_a_reinicio({Archivo, A}) ->
    atomics:put(A, 1, 0),
    arrancar(Archivo, A, enviador(self())),
    {ok, 2} = p43_recordatorios:programar(c1, 10000),
    detener(),
    atomics:put(A, 1, 9880),   % paso el tiempo mientras estaba caido
    arrancar(Archivo, A, enviador(self())),
    ok = p43_recordatorios:revisar(),
    ?assertEqual([{c1, h2}, {c1, h48}], lists:sort(recibir(2))).

%% Prueba de caos: matar el proceso a la fuerza.
sobrevive_a_kill({Archivo, A}) ->
    atomics:put(A, 1, 0),
    Pid = arrancar(Archivo, A, enviador(self())),
    {ok, 2} = p43_recordatorios:programar(c1, 10000),
    Ref = erlang:monitor(process, Pid),
    exit(Pid, kill),
    receive {'DOWN', Ref, process, Pid, _} -> ok after 1000 -> error(sin_down) end,
    arrancar(Archivo, A, enviador(self())),
    ?assertEqual([{h2, pendiente}, {h48, pendiente}],
                 p43_recordatorios:estado(c1)).

falla_se_reintenta_y_se_marca({Archivo, A}) ->
    atomics:put(A, 1, 0),
    arrancar(Archivo, A, fun(_, _) -> {error, sin_red} end),
    {ok, 2} = p43_recordatorios:programar(c1, 10000),
    atomics:put(A, 1, 7120),
    ok = p43_recordatorios:revisar(),
    ?assertEqual([{h2, pendiente}, {h48, pendiente}], p43_recordatorios:estado(c1)),
    ok = p43_recordatorios:revisar(),
    ok = p43_recordatorios:revisar(),
    %% Tras 3 intentos fallidos se marca como fallido, sin perderlo.
    ?assertEqual([{h2, pendiente}, {h48, fallido}], p43_recordatorios:estado(c1)).

excepcion_no_tumba_el_proceso({Archivo, A}) ->
    atomics:put(A, 1, 0),
    Pid = arrancar(Archivo, A, fun(_, _) -> error(boom) end),
    {ok, 2} = p43_recordatorios:programar(c1, 10000),
    atomics:put(A, 1, 7120),
    ?assertEqual(ok, p43_recordatorios:revisar()),
    ?assert(is_process_alive(Pid)),
    ?assertEqual([{h2, pendiente}, {h48, pendiente}], p43_recordatorios:estado(c1)).

cancelar_borra_los_pendientes({Archivo, A}) ->
    atomics:put(A, 1, 0),
    arrancar(Archivo, A, enviador(self())),
    {ok, 2} = p43_recordatorios:programar(c1, 10000),
    ?assertEqual(ok, p43_recordatorios:cancelar(c1)),
    ?assertEqual([], p43_recordatorios:estado(c1)),
    ?assertEqual([], p43_recordatorios:pendientes()).

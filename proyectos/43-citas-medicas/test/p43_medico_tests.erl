-module(p43_medico_tests).
-include_lib("eunit/include/eunit.hrl").

reserva_simple_test() ->
    {ok, M} = p43_medico:start_link(1),
    ?assertEqual(ok, p43_medico:reservar(M, c1, 540, 570)),
    ?assertEqual([{540, 570, c1}], p43_medico:agenda(M)),
    gen_server:stop(M).

traslape_se_rechaza_test() ->
    {ok, M} = p43_medico:start_link(2),
    ok = p43_medico:reservar(M, c1, 540, 570),
    %% Mismo horario, empieza dentro, termina dentro y envuelve.
    ?assertEqual({error, horario_ocupado}, p43_medico:reservar(M, c2, 540, 570)),
    ?assertEqual({error, horario_ocupado}, p43_medico:reservar(M, c3, 555, 600)),
    ?assertEqual({error, horario_ocupado}, p43_medico:reservar(M, c4, 520, 545)),
    ?assertEqual({error, horario_ocupado}, p43_medico:reservar(M, c5, 500, 600)),
    ?assertEqual([{540, 570, c1}], p43_medico:agenda(M)),
    gen_server:stop(M).

citas_pegadas_no_se_traslapan_test() ->
    {ok, M} = p43_medico:start_link(3),
    ok = p43_medico:reservar(M, c1, 540, 570),
    ?assertEqual(ok, p43_medico:reservar(M, c2, 570, 600)),
    ?assertEqual(ok, p43_medico:reservar(M, c3, 510, 540)),
    ?assertEqual([{510, 540, c3}, {540, 570, c1}, {570, 600, c2}],
                 p43_medico:agenda(M)),
    gen_server:stop(M).

cancelar_libera_el_hueco_test() ->
    {ok, M} = p43_medico:start_link(4),
    ok = p43_medico:reservar(M, c1, 540, 570),
    ?assertEqual(ok, p43_medico:cancelar(M, c1)),
    ?assertEqual(ok, p43_medico:reservar(M, c2, 540, 570)),
    ?assertEqual({error, no_existe}, p43_medico:cancelar(M, c1)),
    gen_server:stop(M).

intervalo_invalido_test() ->
    {ok, M} = p43_medico:start_link(5),
    ?assertEqual({error, intervalo_invalido}, p43_medico:reservar(M, c1, 600, 600)),
    ?assertEqual({error, intervalo_invalido}, p43_medico:reservar(M, c2, 600, 540)),
    gen_server:stop(M).

%% El caso del README: muchos pacientes piden el mismo horario a la vez.
simultaneas_solo_una_gana_test() ->
    {ok, M} = p43_medico:start_link(6),
    Padre = self(),
    N = 50,
    [spawn(fun() -> Padre ! {resultado, p43_medico:reservar(M, I, 540, 570)} end)
     || I <- lists:seq(1, N)],
    Resultados = [receive {resultado, R} -> R after 1000 -> timeout end
                  || _ <- lists:seq(1, N)],
    ?assertEqual(1, length([ok || ok <- Resultados])),
    ?assertEqual(N - 1, length([R || {error, horario_ocupado} = R <- Resultados])),
    ?assertEqual(1, length(p43_medico:agenda(M))),
    gen_server:stop(M).

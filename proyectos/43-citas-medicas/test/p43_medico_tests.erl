-module(p43_medico_tests).
-include_lib("eunit/include/eunit.hrl").

-define(D, 740000).

reserva_simple_test() ->
    {ok, M} = p43_medico:start_link(1),
    ?assertEqual(ok, p43_medico:reservar(M, c1, ?D, 540, 570)),
    ?assertEqual([{?D, 540, 570, c1}], p43_medico:agenda(M)),
    gen_server:stop(M).

traslape_se_rechaza_test() ->
    {ok, M} = p43_medico:start_link(2),
    ok = p43_medico:reservar(M, c1, ?D, 540, 570),
    ?assertEqual({error, horario_ocupado}, p43_medico:reservar(M, c2, ?D, 540, 570)),
    ?assertEqual({error, horario_ocupado}, p43_medico:reservar(M, c3, ?D, 555, 600)),
    ?assertEqual({error, horario_ocupado}, p43_medico:reservar(M, c4, ?D, 520, 545)),
    ?assertEqual({error, horario_ocupado}, p43_medico:reservar(M, c5, ?D, 500, 600)),
    ?assertEqual([{?D, 540, 570, c1}], p43_medico:agenda(M)),
    gen_server:stop(M).

citas_pegadas_no_se_traslapan_test() ->
    {ok, M} = p43_medico:start_link(3),
    ok = p43_medico:reservar(M, c1, ?D, 540, 570),
    ?assertEqual(ok, p43_medico:reservar(M, c2, ?D, 570, 600)),
    ?assertEqual(ok, p43_medico:reservar(M, c3, ?D, 510, 540)),
    ?assertEqual([{?D, 510, 540, c3}, {?D, 540, 570, c1}, {?D, 570, 600, c2}],
                 p43_medico:agenda(M)),
    gen_server:stop(M).

mismo_horario_en_dias_distintos_si_test() ->
    {ok, M} = p43_medico:start_link(4),
    ok = p43_medico:reservar(M, c1, ?D, 540, 570),
    ?assertEqual(ok, p43_medico:reservar(M, c2, ?D + 1, 540, 570)),
    ?assertEqual({error, horario_ocupado},
                 p43_medico:reservar(M, c3, ?D + 1, 540, 570)),
    gen_server:stop(M).

agenda_de_un_dia_test() ->
    {ok, M} = p43_medico:start_link(5),
    ok = p43_medico:reservar(M, c1, ?D, 540, 570),
    ok = p43_medico:reservar(M, c2, ?D + 1, 600, 630),
    ?assertEqual([{540, 570, c1}], p43_medico:agenda(M, ?D)),
    ?assertEqual([{600, 630, c2}], p43_medico:agenda(M, ?D + 1)),
    ?assertEqual([], p43_medico:agenda(M, ?D + 2)),
    gen_server:stop(M).

cancelar_libera_el_hueco_test() ->
    {ok, M} = p43_medico:start_link(6),
    ok = p43_medico:reservar(M, c1, ?D, 540, 570),
    ?assertEqual(ok, p43_medico:cancelar(M, c1)),
    ?assertEqual(ok, p43_medico:reservar(M, c2, ?D, 540, 570)),
    ?assertEqual({error, no_existe}, p43_medico:cancelar(M, c1)),
    gen_server:stop(M).

intervalo_invalido_test() ->
    {ok, M} = p43_medico:start_link(7),
    ?assertEqual({error, intervalo_invalido}, p43_medico:reservar(M, c1, ?D, 600, 600)),
    ?assertEqual({error, intervalo_invalido}, p43_medico:reservar(M, c2, ?D, 600, 540)),
    ?assertEqual({error, intervalo_invalido}, p43_medico:reservar(M, c3, ?D, 1400, 1500)),
    gen_server:stop(M).

%% El caso del README: muchos pacientes piden el mismo horario a la vez.
simultaneas_solo_una_gana_test() ->
    {ok, M} = p43_medico:start_link(8),
    Padre = self(),
    N = 50,
    [spawn(fun() -> Padre ! {resultado, p43_medico:reservar(M, I, ?D, 540, 570)} end)
     || I <- lists:seq(1, N)],
    Resultados = [receive {resultado, R} -> R after 1000 -> timeout end
                  || _ <- lists:seq(1, N)],
    ?assertEqual(1, length([ok || ok <- Resultados])),
    ?assertEqual(N - 1, length([R || {error, horario_ocupado} = R <- Resultados])),
    ?assertEqual(1, length(p43_medico:agenda(M))),
    gen_server:stop(M).

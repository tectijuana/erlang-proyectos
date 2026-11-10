-module(p43_clinica_tests).
-include_lib("eunit/include/eunit.hrl").

clinica_test_() ->
    {foreach,
     fun() ->
             {ok, Sup} = p43_citas_medicas_sup:start_link(),
             unlink(Sup),
             timer:sleep(100),
             Sup
     end,
     fun(Sup) ->
             exit(Sup, shutdown),
             timer:sleep(100)
     end,
     [fun(_) -> ?_test(agenda_y_consulta()) end,
      fun(_) -> ?_test(traslape_no_crea_cita()) end,
      fun(_) -> ?_test(cancelar_libera_hueco()) end,
      fun(_) -> ?_test(no_show_libera_hueco()) end,
      fun(_) -> ?_test(simultaneas_en_la_clinica()) end,
      fun(_) -> ?_test(cita_caida_libera_hueco()) end]}.

agenda_y_consulta() ->
    ?assertEqual(ok, p43_clinica:agendar(c1, <<"Ana">>, 1, 540, 570)),
    {ok, Info} = p43_clinica:cita(c1),
    ?assertEqual(agendada, maps:get(estado, Info)),
    ?assertEqual(ok, p43_clinica:confirmar(c1)),
    ?assertEqual(ok, p43_clinica:atender(c1)),
    {ok, Info2} = p43_clinica:cita(c1),
    ?assertEqual(atendida, maps:get(estado, Info2)).

traslape_no_crea_cita() ->
    ok = p43_clinica:agendar(c1, <<"Ana">>, 1, 540, 570),
    ?assertEqual({error, horario_ocupado},
                 p43_clinica:agendar(c2, <<"Luis">>, 1, 555, 600)),
    ?assertEqual({error, no_existe}, p43_clinica:cita(c2)),
    ?assertEqual([c1], p43_clinica:citas()),
    %% Otro medico, mismo horario: si se puede.
    ?assertEqual(ok, p43_clinica:agendar(c3, <<"Luis">>, 2, 540, 570)).

cancelar_libera_hueco() ->
    ok = p43_clinica:agendar(c1, <<"Ana">>, 1, 540, 570),
    ?assertEqual(ok, p43_clinica:cancelar(c1)),
    ?assertEqual({ok, []}, p43_clinica:agenda(1)),
    ?assertEqual(ok, p43_clinica:agendar(c2, <<"Luis">>, 1, 540, 570)).

no_show_libera_hueco() ->
    ok = p43_clinica:agendar(c1, <<"Ana">>, 1, 540, 570),
    ?assertEqual(ok, p43_clinica:no_show(c1)),
    ?assertEqual({ok, []}, p43_clinica:agenda(1)).

simultaneas_en_la_clinica() ->
    Padre = self(),
    N = 30,
    [spawn(fun() ->
                   Padre ! {r, p43_clinica:agendar(I, <<"P">>, 1, 540, 570)}
           end) || I <- lists:seq(1, N)],
    Rs = [receive {r, R} -> R after 2000 -> timeout end
          || _ <- lists:seq(1, N)],
    ?assertEqual(1, length([ok || ok <- Rs])),
    ?assertEqual(1, length(p43_clinica:citas())).

%% Prueba de caos: matar una cita a proposito.
cita_caida_libera_hueco() ->
    ok = p43_clinica:agendar(c1, <<"Ana">>, 1, 540, 570),
    [{c1, CPid, 1}] = ets:lookup(p43_citas_tab, c1),
    exit(CPid, kill),
    timer:sleep(100),
    ?assertEqual({error, no_existe}, p43_clinica:cita(c1)),
    ?assertEqual({ok, []}, p43_clinica:agenda(1)),
    ?assertEqual(ok, p43_clinica:agendar(c2, <<"Luis">>, 1, 540, 570)).

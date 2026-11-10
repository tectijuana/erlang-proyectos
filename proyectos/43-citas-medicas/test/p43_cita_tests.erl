-module(p43_cita_tests).
-include_lib("eunit/include/eunit.hrl").

nueva() ->
    {ok, C} = p43_cita:start_link(#{id => c1,
                                    paciente => <<"Ana Lopez">>,
                                    medico => 1,
                                    inicio => 540,
                                    fin => 570}),
    C.

ciclo_feliz_test() ->
    C = nueva(),
    ?assertEqual(agendada, maps:get(estado, p43_cita:info(C))),
    ?assertEqual(ok, p43_cita:confirmar(C)),
    ?assertEqual(confirmada, maps:get(estado, p43_cita:info(C))),
    ?assertEqual(ok, p43_cita:atender(C)),
    ?assertEqual(atendida, maps:get(estado, p43_cita:info(C))),
    gen_statem:stop(C).

cancelar_desde_agendada_test() ->
    C = nueva(),
    ?assertEqual(ok, p43_cita:cancelar(C)),
    ?assertEqual(cancelada, maps:get(estado, p43_cita:info(C))),
    gen_statem:stop(C).

cancelar_desde_confirmada_test() ->
    C = nueva(),
    ok = p43_cita:confirmar(C),
    ?assertEqual(ok, p43_cita:cancelar(C)),
    ?assertEqual(cancelada, maps:get(estado, p43_cita:info(C))),
    gen_statem:stop(C).

no_show_desde_agendada_test() ->
    C = nueva(),
    ?assertEqual(ok, p43_cita:no_show(C)),
    ?assertEqual(no_show, maps:get(estado, p43_cita:info(C))),
    gen_statem:stop(C).

no_se_atiende_sin_confirmar_test() ->
    C = nueva(),
    ?assertEqual({error, {transicion_invalida, agendada}}, p43_cita:atender(C)),
    ?assertEqual(agendada, maps:get(estado, p43_cita:info(C))),
    gen_statem:stop(C).

estados_finales_no_aceptan_nada_test() ->
    C = nueva(),
    ok = p43_cita:confirmar(C),
    ok = p43_cita:atender(C),
    ?assertEqual({error, {transicion_invalida, atendida}}, p43_cita:cancelar(C)),
    ?assertEqual({error, {transicion_invalida, atendida}}, p43_cita:confirmar(C)),
    ?assertEqual({error, {transicion_invalida, atendida}}, p43_cita:no_show(C)),
    gen_statem:stop(C).

info_trae_los_datos_test() ->
    C = nueva(),
    ?assertEqual(#{id => c1, paciente => <<"Ana Lopez">>, medico => 1,
                   inicio => 540, fin => 570, estado => agendada},
                 p43_cita:info(C)),
    gen_statem:stop(C).

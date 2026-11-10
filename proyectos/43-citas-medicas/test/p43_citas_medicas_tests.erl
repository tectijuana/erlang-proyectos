-module(p43_citas_medicas_tests).
-include_lib("eunit/include/eunit.hrl").

arbol_de_supervision_test_() ->
    {setup,
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
     fun(Sup) ->
             Hijos = [Id || {Id, _, _, _} <- supervisor:which_children(Sup)],
             [?_assert(is_pid(whereis(p43_citas_sup))),
              ?_assert(is_pid(whereis(p43_medicos_sup))),
              ?_assert(is_pid(whereis(p43_clinica))),
              ?_assertEqual(3, length(Hijos)),
              ?_assertEqual(10, length(p43_clinica:medicos()))]
     end}.

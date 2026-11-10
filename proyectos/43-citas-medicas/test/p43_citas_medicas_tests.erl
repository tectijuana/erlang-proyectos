-module(p43_citas_medicas_tests).
-include_lib("eunit/include/eunit.hrl").

arbol_de_supervision_test_() ->
    {setup,
     fun() ->
             Archivo = "/tmp/p43_arbol_" ++
                       integer_to_list(erlang:unique_integer([positive])) ++ ".dets",
             application:set_env(p43_citas_medicas, recordatorios_archivo, Archivo),
             {ok, Sup} = p43_citas_medicas_sup:start_link(),
             unlink(Sup),
             timer:sleep(100),
             {Sup, Archivo}
     end,
     fun({Sup, Archivo}) ->
             exit(Sup, shutdown),
             timer:sleep(100),
             file:delete(Archivo)
     end,
     fun({Sup, _}) ->
             Hijos = [Id || {Id, _, _, _} <- supervisor:which_children(Sup)],
             [?_assert(is_pid(whereis(p43_citas_sup))),
              ?_assert(is_pid(whereis(p43_medicos_sup))),
              ?_assert(is_pid(whereis(p43_recordatorios))),
              ?_assert(is_pid(whereis(p43_clinica))),
              ?_assertEqual(4, length(Hijos)),
              ?_assertEqual(10, length(p43_clinica:medicos()))]
     end}.

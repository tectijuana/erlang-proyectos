-module(p43_simulacion).
-export([run/0]).

-define(BASE, calendar:date_to_gregorian_days(2030, 1, 15)).
-define(ENFERMO, 10).
-define(DURACION, 30).

run() ->
    rand:seed(exsss, {4, 3, 2026}),
    Archivo = "/tmp/p43_sim_" ++
              integer_to_list(erlang:unique_integer([positive])) ++ ".dets",
    application:set_env(p43_citas_medicas, recordatorios_archivo, Archivo),
    case p43_citas_medicas_sup:start_link() of
        {ok, Sup} ->
            unlink(Sup),
            timer:sleep(200),
            {Micro, Res} = timer:tc(fun simular/0),
            reporte(Res, Micro),
            exit(Sup, shutdown),
            timer:sleep(200),
            file:delete(Archivo),
            ok;
        {error, Razon} ->
            io:format("No se pudo arrancar el arbol: ~p~n", [Razon]),
            error
    end.

%%% Simulacion ---------------------------------------------------

simular() ->
    Citas = [cita(I) || I <- lists:seq(1, 200)],

    %% 1. Agendar las 200 citas.
    R1 = [agendar(C) || C <- Citas],

    %% 2. El medico enfermo atiende solo las 5 primeras; las otras 15 quedan pendientes.
    {Enfermo, Sanos} = lists:partition(fun({_, M, _, _}) -> M =:= ?ENFERMO end, Citas),
    {EnfAtendibles, EnfPendientes} = lists:split(5, Enfermo),
    Atendibles = [I || {I, _, _, _} <- Sanos ++ EnfAtendibles],
    Barajadas = [I || {_, I} <- lists:sort([{rand:uniform(), I} || I <- Atendibles])],
    {NoShows, Atienden} = lists:split(40, Barajadas),
    R2 = [p43_clinica:confirmar(I) || I <- Atendibles],
    R3 = [p43_clinica:no_show(I) || I <- NoShows],
    R4 = [p43_clinica:atender(I) || I <- Atienden],

    %% 3. El medico enfermo: cancelar sus 15 y reagendarlas con los otros 9.
    Reag = [reagendar(J, C) || {J, C} <- lists:zip(lists:seq(1, 15), EnfPendientes)],
    Nuevos = [N || {_, _, N} <- Reag],
    ErroresReag = length([x || {C, A, _} <- Reag, C =/= ok orelse A =/= ok]),

    %% 4. Dos pacientes al mismo segundo, 50 veces.
    Carreras = [carrera(R) || R <- lists:seq(1, 50)],
    CarrerasOk = length([x || Rs <- Carreras,
                              length([x || {_, ok} <- Rs]) =:= 1,
                              length([x || {_, {error, horario_ocupado}} <- Rs]) =:= 1]),
    Ganadores = [Id || Rs <- Carreras, {Id, ok} <- Rs],

    %% 5. Verificaciones.
    Agendas = [{M, Ag} || M <- p43_clinica:medicos(), {ok, Ag} <- [p43_clinica:agenda(M)]],
    Traslapes = lists:sum([traslapes(Ag) || {_, Ag} <- Agendas]),
    TotalAgendas = lists:sum([length(Ag) || {_, Ag} <- Agendas]),
    Esperado = 200 - 40 - 15 + 15 + length(Ganadores),

    Terminadas = NoShows ++ Atienden ++ [I || {I, _, _, _} <- EnfPendientes],
    ConRecordatorio = [I || I <- Terminadas, p43_recordatorios:estado(I) =/= []],
    SinRecordatorio = [I || I <- Nuevos ++ Ganadores,
                            p43_recordatorios:estado(I) =/= [{h2, pendiente}, {h48, pendiente}]],

    Anomalias = length([x || X <- R1 ++ R2 ++ R3 ++ R4, X =/= ok]) + ErroresReag,

    Estados = lists:foldl(
                fun(Id, Acc) ->
                        {ok, Info} = p43_clinica:cita(Id),
                        maps:update_with(maps:get(estado, Info), fun(V) -> V + 1 end, 1, Acc)
                end, #{}, p43_clinica:citas()),

    #{anomalias => Anomalias,
      traslapes => Traslapes,
      total_agendas => TotalAgendas,
      esperado => Esperado,
      carreras_ok => CarrerasOk,
      recordatorios_mal => length(ConRecordatorio) + length(SinRecordatorio),
      estados => Estados,
      agendas => [{M, length(Ag)} || {M, Ag} <- Agendas]}.

%%% Auxiliares ---------------------------------------------------

%% Cita I: medico (I-1) rem 10 + 1, 5 horarios de 30 min por dia desde las 9:00.
cita(I) ->
    Medico = ((I - 1) rem 10) + 1,
    K = (I - 1) div 10,
    Dia = ?BASE + K div 5,
    Ini = 540 + (K rem 5) * ?DURACION,
    {I, Medico, Dia, Ini}.

agendar({I, M, Dia, Ini}) ->
    p43_clinica:agendar(I, paciente(I), M, fecha(Dia), Ini, Ini + ?DURACION).

reagendar(J, {Id, _, _, _}) ->
    Cancelada = p43_clinica:cancelar(Id),
    Doc = ((J - 1) rem 9) + 1,
    N = (J - 1) div 9,
    Nuevo = 1000 + J,
    Ini = 540 + N * ?DURACION,
    Agendada = p43_clinica:agendar(Nuevo, paciente(Id), Doc, fecha(?BASE + 5),
                                   Ini, Ini + ?DURACION),
    {Cancelada, Agendada, Nuevo}.

%% Dos procesos esperan la senal "go" y piden el mismo horario a la vez.
carrera(R) ->
    Padre = self(),
    Dia = ?BASE + 6 + (R - 1) div 10,
    Ini = 540 + ((R - 1) rem 10) * ?DURACION,
    Ids = [2000 + 2 * R, 2001 + 2 * R],
    Pids = [spawn(fun() ->
                          receive go ->
                              Padre ! {self(), Id,
                                       p43_clinica:agendar(Id, paciente(Id), 1, fecha(Dia),
                                                           Ini, Ini + ?DURACION)}
                          end
                  end) || Id <- Ids],
    [P ! go || P <- Pids],
    [receive {P, Id, Res} -> {Id, Res} after 2000 -> {P, timeout} end || P <- Pids].

fecha(Dia) -> calendar:gregorian_days_to_date(Dia).

paciente(I) -> list_to_binary("Paciente " ++ integer_to_list(I)).

%% La agenda viene ordenada: basta comparar vecinos del mismo dia.
traslapes([A, B | Resto]) -> choca(A, B) + traslapes([B | Resto]);
traslapes(_) -> 0.

choca({D, _, F, _}, {D, I, _, _}) when I < F -> 1;
choca(_, _) -> 0.

%%% Reporte ------------------------------------------------------

reporte(#{anomalias := An, traslapes := Tr, total_agendas := TA, esperado := Esp,
          carreras_ok := CO, recordatorios_mal := RM, estados := Est,
          agendas := Ag}, Micro) ->
    io:format("~n=== SIMULACION P43 (~p ms) ===~n", [Micro div 1000]),
    io:format("Citas por estado:~n"),
    lists:foreach(fun({E, N}) -> io:format("  ~p: ~p~n", [E, N]) end,
                  lists:sort(maps:to_list(Est))),
    io:format("Citas en agenda por medico: ~p~n", [Ag]),
    io:format("Total en agendas: ~p (esperado ~p)~n", [TA, Esp]),
    io:format("~nVerificaciones:~n"),
    Checks = [{"Ninguna operacion devolvio error", An =:= 0},
              {"Ningun traslape en las agendas", Tr =:= 0},
              {"Las agendas suman lo esperado", TA =:= Esp},
              {"50 carreras: 1 ganador y 1 rechazo en cada una", CO =:= 50},
              {"Recordatorios coherentes con el estado de cada cita", RM =:= 0}],
    lists:foreach(fun({Texto, Ok}) ->
                          io:format("  [~s] ~s~n",
                                    [case Ok of true -> "OK"; false -> "FALLA" end, Texto])
                  end, Checks),
    io:format("~n").

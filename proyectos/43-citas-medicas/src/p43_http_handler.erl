-module(p43_http_handler).
-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, Ruta) ->
    Metodo = cowboy_req:method(Req0),
    Req = try
              manejar(Metodo, Ruta, Req0)
          catch
              Clase:Razon:Pila ->
                  logger:error("error en ~s ~p: ~p:~p ~p",
                               [Metodo, Ruta, Clase, Razon, Pila]),
                  responder(500, #{error => <<"error_interno">>}, Req0)
          end,
    {ok, Req, Ruta}.

%%% Rutas --------------------------------------------------------

manejar(<<"GET">>, medicos, Req) ->
    responder(200, #{medicos => p43_clinica:medicos()}, Req);
manejar(<<"GET">>, citas, Req) ->
    Citas = [cita_json(Info) || Id <- p43_clinica:citas(),
                                {ok, Info} <- [p43_clinica:cita(Id)]],
    responder(200, #{citas => Citas}, Req);
manejar(<<"POST">>, citas, Req0) ->
    case leer_json(Req0) of
        {ok, Cuerpo, Req} -> crear_cita(Cuerpo, Req);
        {error, Req}      -> responder(400, #{error => <<"json_invalido">>}, Req)
    end;
manejar(<<"GET">>, cita, Req) ->
    case id_de(Req) of
        {ok, Id} -> mostrar_cita(Id, Req);
        error    -> id_invalido(Req)
    end;
manejar(<<"POST">>, accion, Req) ->
    case {id_de(Req), accion_de(cowboy_req:binding(accion, Req))} of
        {error, _}               -> id_invalido(Req);
        {_, error}               -> responder(404, #{error => <<"accion_desconocida">>}, Req);
        {{ok, Id}, {ok, Accion}} -> transicion(Id, Accion, Req)
    end;
manejar(<<"GET">>, agenda, Req) ->
    case id_de(Req) of
        error -> id_invalido(Req);
        {ok, Medico} ->
            case lists:keyfind(<<"fecha">>, 1, cowboy_req:parse_qs(Req)) of
                false      -> agenda_completa(Medico, Req);
                {_, Valor} -> agenda_dia(Medico, Valor, Req)
            end
    end;
manejar(_, _, Req) ->
    responder(405, #{error => <<"metodo_no_permitido">>}, Req).

%%% Operaciones --------------------------------------------------

crear_cita(Cuerpo, Req) ->
    case validar(Cuerpo) of
        {ok, Id, Paciente, Medico, Fecha, Ini, Fin} ->
            case p43_clinica:agendar(Id, Paciente, Medico, Fecha, Ini, Fin) of
                ok ->
                    {ok, Info} = p43_clinica:cita(Id),
                    responder(201, cita_json(Info), Req);
                {error, Razon} ->
                    error_resp(Razon, Req)
            end;
        {error, Campo} ->
            responder(400, #{error => <<"campo_invalido">>, campo => Campo}, Req)
    end.

mostrar_cita(Id, Req) ->
    case p43_clinica:cita(Id) of
        {ok, Info}     -> responder(200, cita_json(Info), Req);
        {error, Razon} -> error_resp(Razon, Req)
    end.

transicion(Id, Accion, Req) ->
    case p43_clinica:Accion(Id) of
        ok             -> mostrar_cita(Id, Req);
        {error, Razon} -> error_resp(Razon, Req)
    end.

agenda_completa(Medico, Req) ->
    case p43_clinica:agenda(Medico) of
        {ok, Lista} ->
            Citas = [#{id => C,
                       fecha => fecha_bin(calendar:gregorian_days_to_date(D)),
                       inicio => hora_bin(I),
                       fin => hora_bin(F)} || {D, I, F, C} <- Lista],
            responder(200, #{medico => Medico, citas => Citas}, Req);
        {error, Razon} ->
            error_resp(Razon, Req)
    end.

agenda_dia(Medico, Valor, Req) ->
    case fecha(Valor) of
        error ->
            error_resp(fecha_invalida, Req);
        {ok, Fecha} ->
            case p43_clinica:agenda(Medico, Fecha) of
                {ok, Lista} ->
                    Citas = [#{id => C, inicio => hora_bin(I), fin => hora_bin(F)}
                             || {I, F, C} <- Lista],
                    responder(200, #{medico => Medico, fecha => Valor, citas => Citas}, Req);
                {error, Razon} ->
                    error_resp(Razon, Req)
            end
    end.

%%% Validacion y conversiones -----------------------------------

%% El id es opcional: si no viene, se genera uno.
validar(M) ->
    Id       = maps:get(<<"id">>, M, erlang:system_time(microsecond)),
    Paciente = maps:get(<<"paciente">>, M, undefined),
    Medico   = maps:get(<<"medico">>, M, undefined),
    Fecha    = fecha(maps:get(<<"fecha">>, M, undefined)),
    Ini      = hora(maps:get(<<"inicio">>, M, undefined)),
    Fin      = hora(maps:get(<<"fin">>, M, undefined)),
    Checks = [{<<"id">>,       is_integer(Id)},
              {<<"paciente">>, is_binary(Paciente) andalso Paciente =/= <<>>},
              {<<"medico">>,   is_integer(Medico)},
              {<<"fecha">>,    Fecha =/= error},
              {<<"inicio">>,   Ini =/= error},
              {<<"fin">>,      Fin =/= error}],
    case [Campo || {Campo, false} <- Checks] of
        [] ->
            {ok, F} = Fecha,
            {ok, I} = Ini,
            {ok, N} = Fin,
            {ok, Id, Paciente, Medico, F, I, N};
        [Primero | _] ->
            {error, Primero}
    end.

%% "2030-01-15" -> {ok, {2030,1,15}}. La validez real la revisa la clinica.
fecha(Bin) when is_binary(Bin) ->
    try
        [Y, M, D] = binary:split(Bin, <<"-">>, [global]),
        {ok, {binary_to_integer(Y), binary_to_integer(M), binary_to_integer(D)}}
    catch _:_ -> error
    end;
fecha(_) ->
    error.

%% 540 o "09:00" -> {ok, 540}.
hora(N) when is_integer(N) ->
    {ok, N};
hora(Bin) when is_binary(Bin) ->
    try
        [H, M] = binary:split(Bin, <<":">>),
        {ok, binary_to_integer(H) * 60 + binary_to_integer(M)}
    catch _:_ -> error
    end;
hora(_) ->
    error.

fecha_bin({Y, M, D}) ->
    iolist_to_binary(io_lib:format("~4..0w-~2..0w-~2..0w", [Y, M, D])).

hora_bin(Min) ->
    iolist_to_binary(io_lib:format("~2..0w:~2..0w", [Min div 60, Min rem 60])).

cita_json(Info) ->
    #{id       => maps:get(id, Info),
      paciente => maps:get(paciente, Info),
      medico   => maps:get(medico, Info),
      fecha    => fecha_bin(maps:get(fecha, Info)),
      inicio   => hora_bin(maps:get(inicio, Info)),
      fin      => hora_bin(maps:get(fin, Info)),
      estado   => maps:get(estado, Info)}.

id_de(Req) ->
    try {ok, binary_to_integer(cowboy_req:binding(id, Req))}
    catch error:badarg -> error
    end.

accion_de(<<"confirmar">>) -> {ok, confirmar};
accion_de(<<"atender">>)   -> {ok, atender};
accion_de(<<"cancelar">>)  -> {ok, cancelar};
accion_de(<<"no_show">>)   -> {ok, no_show};
accion_de(_)               -> error.

%%% Respuestas ---------------------------------------------------

leer_json(Req0) ->
    {ok, Datos, Req} = cowboy_req:read_body(Req0),
    try json:decode(Datos) of
        Mapa when is_map(Mapa) -> {ok, Mapa, Req};
        _                      -> {error, Req}
    catch _:_ -> {error, Req}
    end.

id_invalido(Req) ->
    responder(400, #{error => <<"id_invalido">>}, Req).

error_resp(Razon, Req) ->
    responder(estado(Razon), #{error => razon_bin(Razon)}, Req).

estado(no_existe)          -> 404;
estado(medico_no_existe)   -> 404;
estado(horario_ocupado)    -> 409;
estado(cita_duplicada)     -> 409;
estado(fecha_invalida)     -> 422;
estado(intervalo_invalido) -> 422;
estado(_)                  -> 409.

razon_bin(R) when is_atom(R) -> atom_to_binary(R);
razon_bin(R)                 -> iolist_to_binary(io_lib:format("~p", [R])).

responder(Estado, Cuerpo, Req) ->
    cowboy_req:reply(Estado,
                     #{<<"content-type">> => <<"application/json">>},
                     iolist_to_binary(json:encode(Cuerpo)),
                     Req).

-module(plog_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1, config_change/3]).
-export([update_config/0]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    update_config(),
    plog_sup:start_link().

stop(_State) ->
    ok.

config_change(_Changed, _New, _Removed) ->
    update_config().


update_config() ->
    lager:info("Updating plog's config"),
    ModName = plog_cconfig,
    ModSpec = [
            ["-module(",  atom_to_list(ModName), ")."],
            ["-export([should_log/1])."]
            ],
    FuncSpec = [
            ["should_log(", Spec, ") -> ", atom_to_list(Result), ";"]
            || {Spec, Result} <- application:get_env(plog, enable_for, [])
              ],
    TailSpec = [["should_log(_) -> false."]],
    Spec = ModSpec ++ [FuncSpec ++ TailSpec],
    lager:info("Spec = ~s~n", [Spec]),
    mod_gen:go(Spec).





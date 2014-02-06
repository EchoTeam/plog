-module(plog_SUITE).

-define(EUNIT_NOAUTO, true).
-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

-compile(export_all).

%%
%% Init
%%
all() ->
    [
        delta_general_test,
        delta_error_test
    ].

init_per_suite(Config) ->
    ok = application:start(plog),
    Config.

end_per_suite(_Config) ->
    ok = application:stop(plog),
    ok.

init_per_testcase(Config) ->
    [set_val(Name, false) || {Name, _Value} <- application:get_all_env(plog)],
    Config.

set_val(Category, true) ->
    application:set_env(plog, Category, true);
set_val(Category, false) ->
    application:unset_env(plog, Category).

%%
%% Tests
%%
delta_general_test(_Config) ->
    F = fun() -> someresult end,
    [begin
        set_val(cat, JcfgVal),
        ?assertEqual(someresult, plog:delta(cat, sample, F))
    end || JcfgVal <- [false, true]],

    set_val(cat, true),
    ?assertEqual(ok, plog:delta(cat, sample, 1)),

    set_val(cat, false),
    ?assertEqual(ok, plog:delta(cat, sample, something_else)).

delta_error_test(_Config) ->
    F = fun() -> erlang:raise(error, someerror, []) end,
    set_val(cat, true),
    ?assertException(error, someerror, plog:delta(cat, sample, F)).


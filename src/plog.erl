%%% 
%%% Copyright (c) 2009 JackNyfe. All rights reserved.
%%% THIS SOFTWARE IS PROPRIETARY AND CONFIDENTIAL. DO NOT REDISTRIBUTE.
%%% 

%%%
%%% [Asynchronous] Performance Log Module
%%%
%%% vim: ts=4 sts=4 sw=4 expandtab

-module(plog).
-behavior(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([
    % Number of items
    count/2,
    count/3,
    % Size and timing samples (grid)
    combo/2,
    combo/3,
    combo/4,
    combo_count/4,
    % Time samples (deltas) of various operations
    delta/2,
    delta/3,
    extract/0,
    extract/1,
    extract_sample/1,
    format/1,
    magnitude/2,
    magnitude/3,
    median_for_sample/1,
    reset/0,
    % Size samples
    size/2,
    size/3,
    start_link/0,
    % A special sample value (one of a vew distinct values)
    value/2,
    value/3
    ]).

%% TODO: combine all functions into one: submit(Type, Value) instead of
%%   very similar size/magnitude/count/value/...

%% Capturing different categories of timing samples can be enabled on different
%% production machines. All categories are captured in staging environment.

-spec should_log(term()) -> boolean().
should_log(Category) ->
    try plog_cconfig:should_log(Category) 
    catch
        _:_ -> 
            false
    end.

-spec delta(Category :: term(), SampleName :: term(), Arg :: term()) -> 'ok' | term().
delta(Category, SampleName, Arg) ->
    case should_log(Category) of
        true -> delta(SampleName, Arg);
        _ when is_function(Arg, 0) -> Arg();
        _ -> ok
    end.

-spec delta(SampleName :: term(), Fun :: fun() | integer()) -> 'ok' | term().
delta(SampleName, Fun) when is_function(Fun) ->
    Start = now(),
    {Result, Value} = try {ok, Fun()} catch Class:Reason ->
        {error, [Class, Reason, erlang:get_stacktrace()]}
        end,
    Stop = now(),
    TDelta = timer:now_diff(Stop, Start) div 1000,
    gen_server:cast(?MODULE,
        {submit_sample, delta, SampleName, TDelta, Result}),
    case Result of
        ok -> Value;
        error -> erlang:apply(erlang, raise, Value)
    end;
delta(SampleName, TDelta) when is_integer(TDelta) ->
    gen_server:cast(?MODULE,
        {submit_sample, delta, SampleName, TDelta, ok}).

count(Category, SampleName, Arg) ->
    case should_log(Category) of
        true -> count(SampleName, Arg);
        _ when is_function(Arg, 0) -> Arg();
        _ -> ok
    end.

count(SampleName, Fun) when is_function(Fun) ->
    {Result, Value, Count} = try Fun() of
            V when is_list(V) -> {ok, V, length(V)}
        catch Class:Reason ->
            {error, [Class, Reason, erlang:get_stacktrace()], 0}
        end,
    gen_server:cast(?MODULE,
        {submit_sample, count, SampleName, Count, Result}),
    case Result of
        ok -> Value;
        error -> erlang:apply(erlang, raise, Value)
    end;
count(SampleName, Count) when is_integer(Count) ->
    gen_server:cast(?MODULE, {submit_sample, count, SampleName, Count, ok}).

size(Category, SampleName, Arg) ->
    case should_log(Category) of
        true -> size(SampleName, Arg);
        _ when is_function(Arg, 0) -> Arg();
        _ -> ok
    end.

size(SampleName, Fun) when is_function(Fun) ->
    {Result, Value, Size} = try Fun() of
            V when is_binary(V) -> {ok, V, size(V)};
            V -> {ok, V, size(term_to_binary(V))}
        catch Class:Reason ->
            {error, [Class, Reason, erlang:get_stacktrace()], 0}
        end,
    gen_server:cast(?MODULE,
        {submit_sample, size, SampleName, Size, Result}),
    case Result of
        ok -> Value;
        error -> erlang:apply(erlang, raise, Value)
    end;
size(SampleName, Size) when is_integer(Size) ->
    gen_server:cast(?MODULE,
        {submit_sample, size, SampleName, Size, ok}).

%% Used if we need to store performance log for the specific counter term,
%% such as true or false:
%% value(?MODULE, moderator_access, true)
value(Category, SampleName, Arg) ->
    case should_log(Category) of
        true -> value(SampleName, Arg);
        _ when not(is_tuple(Arg)) andalso is_function(Arg, 0) -> Arg();
        _ -> ok
    end.

value(SampleName, Fun) when is_function(Fun) ->
    {Result, Value} = try {ok, Fun()}
        catch Class:Reason ->
            {error, [Class, Reason, erlang:get_stacktrace()]}
        end,
    gen_server:cast(?MODULE,
        {submit_sample, value, SampleName, Value, Result}),
    case Result of
        ok -> Value;
        error -> erlang:apply(erlang, raise, Value)
    end;
value(SampleName, Value) ->
    gen_server:cast(?MODULE,
        {submit_sample, value, SampleName, Value, ok}).

combo(Category, SampleName, Arg) ->
    case should_log(Category) of
        true -> combo(SampleName, Arg);
        _ when is_function(Arg, 0) -> Arg();
        _ -> ok
    end.

combo(Category, SampleName, Data, TDelta) ->
    case should_log(Category) of
      true when is_binary(Data) -> combo(SampleName, {size(Data), TDelta});
      true -> combo(SampleName, {size(term_to_binary(Data)), TDelta});
      _ -> ok
    end.

combo(SampleName, Fun) when is_function(Fun) ->
    Start = now(),
    {Result, Value, Size} = try Fun() of
            V when is_binary(V) -> {ok, V, size(V)};
            V -> {ok, V, size(term_to_binary(V))}
        catch Class:Reason ->
            {error, [Class, Reason, erlang:get_stacktrace()], 0}
        end,
    Stop = now(),
    TDelta = timer:now_diff(Stop, Start) div 1000,
    gen_server:cast(?MODULE,
        {submit_sample, combo, SampleName, {Size, TDelta}, Result}),
    case Result of
        ok -> Value;
        error -> erlang:apply(erlang, raise, Value)
    end;
combo(SampleName, {Size, TDelta}) when is_integer(Size), is_integer(TDelta) ->
    gen_server:cast(?MODULE,
        {submit_sample, combo, SampleName, {Size, TDelta}, ok}).

combo_count(Category, SampleName, Count, TDelta) 
                when is_integer(Count) andalso is_integer(TDelta) ->
    case should_log(Category) of
      true -> combo_count(SampleName, {Count, TDelta});
      _ -> nop
    end.
% internal usage
combo_count(SampleName, {Count, TDelta}) when is_integer(Count), is_integer(TDelta) ->
    gen_server:cast(?MODULE,
        {submit_sample, combo_count, SampleName, {Count, TDelta}, ok}).

magnitude(Category, SampleName, Arg) ->
    case should_log(Category) of
        true -> magnitude(SampleName, Arg);
        _ when not(is_tuple(Arg)) andalso is_function(Arg, 0) -> Arg();
        _ -> ok
    end.

magnitude(SampleName, Fun) when is_function(Fun) ->
    {Result, Value} = try {ok, Fun()}
        catch Class:Reason ->
            {error, [Class, Reason, erlang:get_stacktrace()]}
        end,
    gen_server:cast(?MODULE,
        {submit_sample, magnitude, SampleName, Value, Result}),
    case Result of
        ok -> Value;
        error -> erlang:apply(erlang, raise, Value)
    end;
magnitude(SampleName, Value) ->
    gen_server:cast(?MODULE,
        {submit_sample, magnitude, SampleName, Value, ok}).

reset() ->
    gen_server:call(plog, delete_all_objects).

extract() -> extract(fun(_) -> true end).
extract(Slot) when is_atom(Slot) ->
        extract(fun({SlotName, _, _} = _Entry) -> Slot == SlotName end);
extract(EntryFilter) when is_function(EntryFilter, 1) ->
    Entries = [{{SampleName, SlotName},
            {SampleName, WithinSlot, Result, Mavg}}
        || {SlotName, {SampleName, WithinSlot, Result}, Mavg} = Entry
            <- ets:tab2list(tab()),
            EntryFilter(Entry)],
    GroupedEntries = list_utils:group_by_key(1, lists:keysort(1, Entries)),
    lists:sort(fun sort_by_group_activity/2,
        [add_total_value(sort_snd([],
            slot_name_as_group_header(Sublist)))
            || Sublist <- GroupedEntries]).

extract_sample(Name) -> [  
        {SlotName, WithinSlot, Result, Mavg}
        ||
        {SlotName, {SampleName, WithinSlot, Result}, Mavg}
                <- ets:tab2list(tab()),
        SampleName == Name
].

median_for_sample(Name) ->
    case extract_sample(Name) of
        [] -> undefined;
        Entries ->
            Slots = [{WithinSlot, jn_mavg:get_current(Mavg)} || {_, WithinSlot, _, Mavg} <- Entries],
            RankedSlots = lists:sort(fun sort_by_eps/2, Slots),
            element(1, hd(RankedSlots))
    end.

% Sort second element of the tuple.
sort_snd(SortArgs, {Key, List}) ->
    {Key, erlang:apply(lists, sort, SortArgs ++ [List])}.

slot_name_as_group_header([{{_SampleName, SlotName}, _}|_] = List) ->
    {SlotName, [V || {_, V} <- List]}.

format(GroupedList) ->
    lists:flatten(lists:map(fun
    ({ComboType, [{SampleName, _WithinSlot, _Result, _Mavg}|_] = List}) 
                when ComboType == combo orelse ComboType == combo_count ->
      {Epd, [{95, P95}, {98, P98}], Grid} = format_2d_grid([95, 98], List),
      AuxInfo = lists:flatten(io_lib:format("~bepm,~pms@95%,~pms@98%",
            [Epd div (86400 div 60), P95, P98])),
      [io_lib:format("~s ~s~n",
            [fit_in(78 - length(AuxInfo), SampleName), AuxInfo]),
        format_grid(Grid,
            [{align, right}])];
    ({value, [{SampleName, _WithinSlot, _Result, _Mavg}|_] = List}) ->
      {_Epd, _, Grid} = format_1d_grid([], List, value),
      [io_lib:format("~p~n", [SampleName]),
        format_grid(Grid,
            [{first_column_align, left}, {align, right}])];
    ({SlotName, [{SampleName, _WithinSlot, _Result, _Mavg}|_] = List}) ->
      {Epd, [{95, P95}, {98, P98}], Grid} = format_1d_grid([95, 98], List, SlotName),
      AuxInfo = lists:flatten(io_lib:format("~bepm,~pms@95%,~pms@98%",
            [Epd div (86400 div 60), P95, P98])),
      [io_lib:format("~s ~s~n",
            [fit_in(78 - length(AuxInfo), SampleName), AuxInfo]),
        format_grid(Grid,
            [{first_column_align, right}, {align, right}])]

    end, GroupedList)).

% Like string:left(), but does not truncate if does not fit.
fit_in(N, Term) ->
    S = lists:flatten(io_lib:format("~p", [Term])),
    if length(S) =< N -> string:left(S, N); true -> S end.

mavg_info_columns(Mavg) ->
    {Period, _Cts, _Lts} = jn_mavg:getProperties(Mavg),
    {Present, History, Total} = jn_mavg:history(Mavg),
    [jn_mavg:getEventsPer(Mavg, 1),
     jn_mavg:getEventsPer(Mavg, 60),
     ["[", integer_to_list(Present)] | History]
    ++ [ ["|", integer_to_list(Present + Total), "]"],
         [integer_to_list(Period), "avg"]].

format_1d_grid(PercentilePoints, List, SlotName) ->
    Unit = case SlotName of delta -> ms; count -> number; size -> bytes; value -> value; magnitude -> magnitude end,
    Header = [Unit, eps, epm],
    Body = [begin
        {Err1, Err2} = case Result of
                ok -> {"", []};
                error -> {"# ", ["(errors!)"]}
            end,
        [io_lib:format("~s~p", [Err1, WithinSlot])
            | mavg_info_columns(Mavg) ++ Err2]
      end || {_, WithinSlot, Result, Mavg} <- List],
    [TotalEpd] = [V || {total, V} <- List],
    {TotalEpd,
        percentiles(TotalEpd, PercentilePoints, [{WithinSlot,
            jn_mavg:getEventsPer(Mavg, 86400)}
            || {_, WithinSlot, _, Mavg} <- List]),
    [Header] ++ Body ++ [[total,
        TotalEpd div 86400, TotalEpd div (86400 div 60)]]}.

format_2d_grid(PercentilePoints, List) ->
    RowNames = lists:usort([V || {_, {V, _}, _, _} <- List]),
    ColNames = lists:usort([V || {_, {_, V}, _, _} <- List]),
    Header = [bytes, eps, epm] ++ ColNames ++ [ms],
    TaggedBody = [
      [begin
        Cells = [{Result, Mavg} || {_, Cell, Result, Mavg} <- List,
                Cell == {RowName, ColName}],
        case Cells of
          [] -> {0, "-"};
          _ ->
            {ErrS, Epd} = case Cells of
              [{ok, Mavg}] ->
                {"", jn_mavg:getEventsPer(Mavg, 86400)};
              [{error, Mavg}] ->
                {"!", jn_mavg:getEventsPer(Mavg, 86400)};
              [{_, Mavg1},{_, Mavg2}] -> {"!",
                (jn_mavg:getEventsPer(Mavg1, 86400)
                + jn_mavg:getEventsPer(Mavg2, 86400))}
            end,
            WS = integer_to_list(Epd div (86400 div 60)),
            {Epd, [ErrS, WS]}
        end
      end || ColName <- ColNames]
    || RowName <- RowNames],

    MsColumnFreqs = [{ColName, lists:sum([Epd || {Epd, _} <- ColValues])}
        || [ColName | ColValues]
            <- transpose([ColNames|TaggedBody])],

    Body = [begin
        RowEpd = lists:sum([Epd || {Epd, _} <- Columns]),
        [RowName, RowEpd div 86400, RowEpd div (86400 div 60)
            | [Cell || {_, Cell} <- Columns]]
        end || {RowName, Columns} <- lists:zip(RowNames, TaggedBody)],

    [TotalEpd] = [V || {total, V} <- List],
    {TotalEpd,
    percentiles(TotalEpd, PercentilePoints, MsColumnFreqs),
    [Header]
    ++ Body
    ++ [[total, TotalEpd div 86400, TotalEpd div (86400 div 60)]]}.

%% @percentiles(Epd, [Percentile], [{term(), Value}] -> [{Percentile, term()}]
%% @percentiles(int(), [int()], [{term(), int()}] -> [{int(), term()}]
percentiles(TotalEpd, PercentilePoints, List) ->
    element(1, lists:foldl(fun
        ({WithinSlot, Epd}, {Percentiles, EpdSoFar}) ->
        NewEpdSoFar = EpdSoFar + Epd,
        {lists:map(fun
            ({P, uncertain}) ->
                case NewEpdSoFar >= (0.95 * TotalEpd) of
                    true -> {P, WithinSlot};
                    _ -> {P, uncertain}
                end;
            (OldValue) -> OldValue
        end, Percentiles), NewEpdSoFar}
        end, {[{P, uncertain} || P <- PercentilePoints], 0}, List)).

%% Server performance logging server implementation.

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-record(state, {tab}).

init([]) ->
    Tab = ets:new(?MODULE, [{keypos, 2}]),
    {ok, #state{ tab = Tab }}.

handle_call(get_tab, _From, State) -> {reply, State#state.tab, State};
handle_call(delete_all_objects, _From, State) ->
    ets:delete_all_objects(State#state.tab),
    {reply, ok, State}.

handle_cast({submit_sample, SlotName, SampleName, Measurement, Result}, #state{tab=T} = State) ->
    Key = {SampleName, within(SlotName, Measurement), Result},
    V = ma_val(SlotName, Measurement), 
    NewValue = case ets:lookup(T, Key) of
      [{SlotName, _, Mavg}] -> {SlotName, Key, jn_mavg:bump_mavg(Mavg, V)};
      [] ->  {SlotName, Key, jn_mavg:new_mavg(300, [{start_events, V}])}
    end,
    ets:insert(T, NewValue),
    {noreply, State}.

handle_info(_, State) -> {noreply, State}.

code_change(_OldVsn, State, _Extra) -> {ok, State}.
terminate(_Reason, _State) -> ok.

%%% Internal functions

tab() -> gen_server:call(?MODULE, get_tab).

add_total_value({SlotName, List}) ->
    TotalEpd = lists:sum([jn_mavg:getEventsPer(Mavg, 86400)
        || {_, _, _, Mavg} <- List]),
    {SlotName, List ++ [{total, TotalEpd}]}.

sort_by_group_activity({_, A}, {_, B}) ->
    [ATotal] = [T || {total, T} <- A],
    [BTotal] = [T || {total, T} <- B],
    ATotal > BTotal.

sort_by_eps({_SlotA, EPSA}, {_SlotB, EPSB}) ->
    EPSA > EPSB.

%% Select an appropriate delta slot for the measurement.
within(_rid, error) -> error;
within(delta, TDelta) -> within(delta_grid(), TDelta);
within(size, Size) -> within(size_grid(), Size);
within(count, Count) -> within(count_grid(), Count);
within(value, Value) -> Value;
within(magnitude, _) -> nocare;
within(combo, {Size, TDelta}) ->
    {within(size_grid(), Size), within(delta_grid(), TDelta)};
within(combo_count, {Count, TDelta}) ->
    {within(count_grid(), Count), within(delta_grid(), TDelta)};
within(Grid, Value) -> hd([Slot || Slot <- Grid, Value =< Slot]).

ma_val(magnitude, Magnitude) -> Magnitude;
ma_val(_, _) -> 1.

delta_grid() -> [1, 3, 5, 10, 20, 30, 50, 75, 100, 200, 300, 500,
        750, 1000, 1500, 2000, 3000, 5000, 10000, 30000, infinity].

size_grid() -> [0, 96, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072,
        262144, 524288, 1048576, 4000000, 8000000, 16000000, 32000000,
        infinity].

count_grid() -> [1, 3, 5, 10, 20, 30, 50, 75, 100, 200, 300, 500,
        750, 1000, 1500, 2000, 3000, 5000, 10000, 30000, infinity].

format_grid(RawList) -> format_grid(RawList, []).
format_grid(RawList, Options) ->
    % Make sure the list is formatted out of strings
    List = [[lists:flatten(case Cell of
            V when is_list(V) -> V;
            V when is_atom(V) -> atom_to_list(V);
            V when is_integer(V) -> integer_to_list(V);
            V when is_float(V) -> float_to_list(V);
            V when is_tuple(V) -> io_lib:format("~p", [V])
        end) || Cell <- Row] || Row <- RawList],
    [Alignment, ColumnSeparator,
     FirstColumnAlignment,
     FirstColumnLeftIndent, FirstColumnRightIndent] = [
        proplists:get_value(Item, Options, Default)
        || {Item, Default} <- [
            {align, left},
            {column_separator, " "},
            {first_column_align,
                proplists:get_value(align, Options, right)},
            {first_column_left_indent, 2},
            {first_column_right_indent, 2}
        ]],
    ColumnWidths = grid_compute_column_widths(List),
    FormatRow = fun(Row) ->
        [string_utils:intersperse(ColumnSeparator,
        [grid_format_cell(Alignment, FirstColumnAlignment,
            FirstColumnLeftIndent, FirstColumnRightIndent,
            N, ColWidth, Value)
        || {N, Value, ColWidth} <- grid_zip(0, Row, ColumnWidths, "")
         ]), "\n"]
    end,
    [FormatRow(Row) || Row <- List].

grid_format_cell(_Alignment, FirstColumnAlignment, FirstColumnLeftIndent, FirstColumnRightIndent, 0, MaxWidth, Value)
    when FirstColumnAlignment == left; FirstColumnAlignment == right; FirstColumnAlignment == centre ->
    [string:chars($ , FirstColumnLeftIndent),
     string:FirstColumnAlignment(Value, MaxWidth),
     string:chars($ , FirstColumnRightIndent)];
grid_format_cell(Alignment, _, _, _, _N, MaxWidth, Value)
    when Alignment == left; Alignment == right; Alignment == centre ->
    string:Alignment(Value, MaxWidth).

% Produce one-dimensional list of widths for the corresponding columns.
grid_compute_column_widths(List) ->
    GridOfLengths = [[length(Cell) || Cell <- Row] || Row <- List],
    lists:map(fun lists:max/1, transpose(GridOfLengths)).

%% Zip two lists, making sure missing items in list A are replaced with Default.
%% @spec grid_zip(A, B, Default) -> [{A, B}]
grid_zip(N, [A|ARest], [B|BRest], Default) ->
    [{N, A, B} | grid_zip(N+1, ARest, BRest, Default)];
grid_zip(N, [], [B|BRest], Default) ->
    [{N, Default, B} | grid_zip(N+1, [], BRest, Default)];
grid_zip(_N, [], [], _Default) -> [].

% Transpose rows and columns of the given grid.
% http://www.haskell.org/ghc/docs/latest/html/libraries/base/Data-List.html#v:transpose
% @spec transpose([[term()]]) -> [[term()]]
transpose([]) -> [];
transpose([[]|XSS]) -> transpose(XSS);
transpose([[X|XS]|XSS]) ->
    [[X|[H||[H|_]<-XSS]] | transpose([XS|[T||[_|T]<-XSS]])].

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

delta_test_() ->
    {setup,
        fun delta_setup/0,
        fun delta_cleanup/1,
        [{"general", fun test_delta_general/0},
        {"error", fun test_delta_error/0}]
    }.

delta_setup() ->
    meck:new(plog_cconfig, [non_strict]).

delta_cleanup(_) ->
    meck:unload().

delta_plog_cconfig_val(Value) ->
    meck:expect(plog_cconfig, should_log, 1, Value).

test_delta_general() ->
    F = fun() -> someresult end,
    [begin
        delta_plog_cconfig_val(JcfgVal),
        ?assertEqual(someresult, delta(cat, sample, F))
    end || JcfgVal <- [false, true]],

    delta_plog_cconfig_val(true),
    ?assertEqual(ok, delta(cat, sample, 1)),

    delta_plog_cconfig_val(false),
    ?assertEqual(ok, delta(cat, sample, something_else)).

test_delta_error() ->
    F = fun() -> erlang:raise(error, someerror, []) end,
    delta_plog_cconfig_val(true),
    ?assertEqual(ok, try
            delta(cat, sample, F)
        catch
            error:someerror ->
                ok;
            _:_ ->
                no
        end
    ).

-endif.

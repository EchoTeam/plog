-module(plog_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Specs = [{ plog, { plog, start_link, [] },
              permanent, 10000, worker, [ plog, jn_mavg ] }
            ],
    {ok, { {one_for_one, 5, 10}, Specs} }.


Performance Logging
==

This application provides different kinds of statistics about performance in
erlang enviroment.

There are diffrerent types of counters:
* delta -- time samples (deltas) of various operations
* magnitude 
* size
* value
* count -- number of items
* combo -- size and timing samples (size + delta)
* combo_count -- number of items and timing samples (count + delta)

Usage example
==

Consider a situation when you want to get execution time of some function -- let
it be json to xml convertation. With plog you could simply write:

    Xml = plog:delta(hot_part, json_to_xml, fun () ->
            json_to_xml_converter:convert(Json)
        end).

Now you should turn `plog` application (e.g. `application:start(plog)`) and enable 
category `hot_part` for activating logging: `application:set_env(plog, hot_part, true)`.

That is all.

Now you could watch the statistics: attach to the node and execute `plog:print()` or
`plog:print(delta)` to print only delta-statistic. The output would be looks like: 

        json_to_xml                                     990epm,20ms@95%,20ms@98%
           ms   eps epm
            1     3 169  [616  878  792  779 |3969814] 300avg
            3     5 308 [1183 1435 1499 1461 |6294807] 300avg
            5     4 220  [792 1063 1157 1142 |4573967] 300avg
           10     4 212  [726 1041 1176 1269 |4850060] 300avg
           20     1  74  [259  357  411  412 |1853697] 300avg
           30     0   6   [21   24   51   35  |214992] 300avg
           50     0   1    [3    1    5    2   |46119] 300avg
           75     0   0    [0    1    2    0   |17593] 300avg
          100     0   0    [0    0    4    0    |8161] 300avg
          200     0   0    [0    0    3    0     |926] 300avg
          300     0   0    [0    0    0    0      |70] 300avg
          500     0   0    [0    0    0    0      |53] 300avg
          750     0   0    [0    0    0    0      |10] 300avg
        total    16 990

It is mean that in the last minute it was about 990 event in total. 169 events per minute took
<= 1 ms to execute, 308 events took from 1 to 3 ms to execute and so on. You could also
see that 95% (and 98% in particular this case too) of all events took less than 20ms.

Please refer to `src/plog.erl` to obtain more information.


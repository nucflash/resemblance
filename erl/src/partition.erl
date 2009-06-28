-module(partition).
-export([start_fn/0, partition/2]).
-include("debug.hrl").

start_fn() ->
    NewWorkerFn = 
	fun(InFile,OutFile) ->
		spawn(?MODULE,partition,[InFile,OutFile])
	end,
    NewWorkerFn.

partition(InputFilename, OutFilename) ->
    d("in ~p out ~p\n",[InputFilename,OutFilename]),
    PartitionOutputFiles = open_partition_file_handles(OutFilename),    
    read_and_partition(InputFilename, PartitionOutputFiles),
    close_all_files(PartitionOutputFiles),
    util:ack_response().

open_partition_file_handles(OutFilename) ->
    file_util:ensure_output_dir_created(),
    Filenames = partition_filenames(OutFilename),
    io:format("Filename ~p\n",[Filenames]),
    [ bin_parser:open_file_for_write(Filename) || Filename <- Filenames ].

partition_filenames(OutFilename) ->
    [ OutFilename ++".p"++integer_to_list(ON-1)
      || ON <- lists:seq(1,opts:int_prop(num_partitions,10)) ].
   
read_and_partition(Filename, PartitionOutputFiles) ->
    F = bin_parser:open_file_for_read(Filename),
    read_term_and_partition(F, PartitionOutputFiles).

read_term_and_partition(F, PartitionOutputFiles) ->
    Parsed = bin_parser:read(F),
    case Parsed of
	eof -> 
	    done;
	{ok,KV} -> 
	    send_to_partition(KV, PartitionOutputFiles),
	    read_term_and_partition(F, PartitionOutputFiles)
    end.

send_to_partition({Key,_Value}=KeyValue, PartitionOutputFiles) ->
    Idx = (erlang:phash2(Key) rem length(PartitionOutputFiles)) + 1,
    FH = lists:nth(Idx, PartitionOutputFiles),
    bin_parser:write(FH, KeyValue).

close_all_files(Files) ->
    lists:foreach(fun(F) -> file:close(F) end, Files).

   

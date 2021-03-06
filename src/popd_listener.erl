%%%-------------------------------------------------------------------
%%% @author  <Kuleshov Alexander>
%%% @copyright (C) 2011, 
%%% @doc
%%%
%%% @end
%%% Created : 10 Jan 2011 by  <kuleshovmail@gmail.com>
%%%-------------------------------------------------------------------
-module(popd_listener).

-behaviour(gen_server).

-export([start_link/0, stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-export([accept/1]).
-export([receive_loop/3]).

-include_lib("../include/pop.hrl").

-define(SERVER, ?MODULE).

start_link()  ->
    maildir:create_key_value_user_pass_db("Users"),
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

accept(Socket) ->
    case gen_tcp:accept(Socket) of
	{ok, Sock} ->
	     spawn(?MODULE, receive_loop, [Sock, [], []]),
             gen_tcp:send(Sock, "+OK POP3 server ready \r\n"),
  	     accept(Socket);
	{error, Reason} ->
	    Reason
    end.

receive_loop(Socket, UserName, Password) ->
    io:format("HELLLO \n"),
    case gen_tcp:recv(Socket, 0) of
	 {ok, Data} ->
	    
	  ReParseData = string:to_lower(utils:trim(Data)),
	  
	     %% User login command
          try
	      case pop_messages:is_message_user(ReParseData) of 
		  { _ , Name } ->
		      if
			  (length(Name) == 1) ->
			      gen_tcp:send(Socket, pop_messages:ok_message() ++ "\r\n"),
			      receive_loop(Socket, Name, []);
			  true ->
			      receive_loop(Socket, [], [])
		      end;  
		  error ->
		      error  
	      end
	  catch _:_ -> gen_tcp:close(Socket)
          end,
 
	      %% password getting
	  try
	      case pop_messages:is_message_pass(ReParseData) of
		  { _ , Pass } ->
		      if
			  (length(Pass) == 1) ->
			      gen_tcp:send(Socket, pop_messages:ok_message() ++ "\r\n"),
			      receive_loop(Socket, UserName, Pass);
			  true ->
			      receive_loop(Socket, [], [])
		      end;
		  error ->
		      error
	      end
	  catch _:_ -> gen_tcp:close(Socket)
	  end,
	    
	        %% LIST command
	  try
	      case pop_messages:is_message_list(ReParseData) of
		  { _ , _ } ->
		      receive_loop(Socket, UserName, Password);
		  {_} ->
		      receive_loop(Socket, UserName, Password);
		  error ->
		      error
	      end
	  catch _:_ -> gen_tcp:close(Socket)
	  end,

	         %% RETR command
	 try
	     case pop_messages:is_message_retr(ReParseData) of
		 { _ , _ } ->
		     receive_loop(Socket, UserName, Password);
		 error ->
		     error
	     end
	 catch _:_ -> gen_tcp:close(Socket)
	 end,

	          %% DELE command
	  try
	      case pop_messages:is_message_dele(ReParseData) of
		  { _ , _ } ->
		      receive_loop(Socket, UserName, Password);
		  error ->
		      error
	      end
	  catch _:_ -> gen_tcp:close(Socket)
	  end,

	  	   %% Other command without atguments
	  try
	      case ReParseData of
		  "quit" ->
		      gen_tcp:send(Socket, pop_messages:ok_message() ++ " POP3 server signing off\r\n"),
		      gen_tcp:close(Socket);
		  "noop" ->
		      gen_tcp:send(Socket, pop_messages:ok_message() ++ "\r\n"),
		      receive_loop(Socket, [], []);
		  "stat" ->
		      gen_tcp:send(Socket, 1),
		      receive_loop(Socket, UserName, Password);
		  "rset" ->
		      receive_loop(Socket, UserName, Password);
		  _ ->
		      gen_tcp:send(Socket, pop_messages:err_message()),
		      receive_loop(Socket, [], [])	
	      end
	  catch _:_ -> gen_tcp:close(Socket)
	  end;

	{error, closed} ->
	    ok
    end.
    
    
stop() ->
    io:format("Pop3 server stop! \n "),
    gen_server:cast(?MODULE, stop).

% 
% Callback functions
%
init([]) ->
    Port = 110,
    Opts = [list, {reuseaddr, true}, 
            {keepalive, false}, {ip,{0,0,0,0}}, {active, false}],

    case gen_tcp:listen(Port, Opts) of
	 {ok, ListenSocket} ->
              spawn(?MODULE, accept, [ListenSocket]),
	      {ok, #state{ listener = ListenSocket}};
         {error, Reason} ->
	     {stop, Reason}
    end.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(stop, State) ->
    {stop, normal, State}.

handle_info(_Info, State) ->
    {noreply, State}.
%

%
% terminate server
%
terminate(_Reason, State) ->
    %maildir:destroy(),
    gen_tcp:close(State#state.listener),
    ok.

%
% Hot code change
%
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
%

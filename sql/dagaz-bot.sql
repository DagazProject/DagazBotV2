--
-- PostgreSQL database dump
--

-- Dumped from database version 11.1
-- Dumped by pg_dump version 11.1

-- Started on 2024-01-02 13:54:39

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 273 (class 1255 OID 1813623)
-- Name: addcommand(integer, integer); Type: FUNCTION; Schema: public; Owner: lora_server
--

CREATE FUNCTION public.addcommand(pcontext integer, paction integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
  r integer;
begin
  insert into command_queue(context_id, action_id) 
  values (pContext, pAction)
  returning id into r;
  return r;
end;
$$;


ALTER FUNCTION public.addcommand(pcontext integer, paction integer) OWNER TO lora_server;

--
-- TOC entry 288 (class 1255 OID 1810140)
-- Name: chooseaccount(integer, text, integer); Type: FUNCTION; Schema: public; Owner: dagaz
--

CREATE FUNCTION public.chooseaccount(puser integer, paccount text, pserver integer) RETURNS json
    LANGUAGE plpgsql STABLE
    AS $$
declare
  r json;
  x record;
  lAccount text default null;
  lPass text default null;
begin
  select string_agg(b.value, ',') into lAccount
  from   account a
  inner  join user_param b on (b.account_id = a.id and b.type_id = 2)
  where  a.user_id = pUser and a.server_id = pServer and a.deleted is null
  and    coalesce(pAccount, b.value) = b.value;
  if not lAccount is null then
     select e.value as pass into lPass
     from   account c
     inner  join user_param d on (d.account_id = c.id and d.type_id = 2 and d.value = lAccount)
     inner  join user_param e on (e.account_id = c.id and e.type_id = 3);
  end if;
  for x in
      select case
               when lAccount is null then 0
               when strpos(lAccount, ',') = 0 then 1
               else 2 
             end as result, lAccount as login, lPass as password
  loop
      r := row_to_json(x);  
  end loop;
  return r;
end;
$$;


ALTER FUNCTION public.chooseaccount(puser integer, paccount text, pserver integer) OWNER TO dagaz;

--
-- TOC entry 274 (class 1255 OID 1828710)
-- Name: clearactivity(integer); Type: FUNCTION; Schema: public; Owner: lora_server
--

CREATE FUNCTION public.clearactivity(pid integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
begin
  delete from command_param
  where command_id in ( select id from command_queue where context_id = pId );
  delete from command_queue where context_id = pId;
  update common_context set action_id = null, wait_for = null, scheduled = null, delete_message = null
  where id = pId;
end;
$$;


ALTER FUNCTION public.clearactivity(pid integer) OWNER TO lora_server;

--
-- TOC entry 290 (class 1255 OID 1810141)
-- Name: createaccount(integer, integer); Type: FUNCTION; Schema: public; Owner: dagaz
--

CREATE FUNCTION public.createaccount(puser integer, pserver integer) RETURNS json
    LANGUAGE plpgsql
    AS $$
          declare
            pLogin text;
            pAccount integer default null;
            r json;
            x record;
          begin
            select value into strict pLogin
            from   user_param
            where  user_id = pUser and type_id = 2;
            select max(a.id) into pAccount
            from   account a
            inner  join user_param b on (b.account_id = a.id)
            where  a.user_id = pUser and b.value = pLogin;
            if pAccount is null then
               insert into account(user_id, server_id)
               values (pUser, pServer)
               returning id into pAccount;  
            else
               delete from user_param
               where account_id = pAccount and type_id in (2, 3, 4);
            end if;
            update user_param set account_id = pAccount, user_id = null
            where user_id = pUser and type_id in (2, 3, 4);
            for x in
                select 1 result, pAccount as id
            loop
                r := row_to_json(x);  
            end loop;
            return r;
          end;
$$;


ALTER FUNCTION public.createaccount(puser integer, pserver integer) OWNER TO dagaz;

--
-- TOC entry 291 (class 1255 OID 1810142)
-- Name: createuser(text, bigint, text, text, text); Type: FUNCTION; Schema: public; Owner: dagaz
--

CREATE FUNCTION public.createuser(plogin text, pchatid bigint, pfirst text, plast text, plocale text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
            declare
               lUser integer;
               lCn integer;
               lCtx integer default null;
            begin
               select max(id), max(context_id) into lUser, lCtx from users where username = pLogin;
               if lCtx is null then
                  insert into common_context default values
                  returning id into lCtx;
               end if;
               if not lUser is null then
                  update users set updated = now(), firstname = pFirst, lastname = pLast, chat_id = pChatId
                  where id = lUser;
               else
                  insert into users (username, firstname, lastname, chat_id, context_id)
                  values (pLogin, pFirst, pLast, pChatId, lCtx)
                  returning id into lUser;
               end if;
               update user_param set created = now(), value = pLocale where user_id = lUser and type_id = 7;
               get diagnostics lCn = row_count;
               if lCn = 0 then
                  insert into user_param(type_id, user_id, value)
                  values (7, lUser, pLocale);
               end if;
               insert into command_queue(context_id, action_id) values (lCtx, 201);
               return lUser;
            end;
$$;


ALTER FUNCTION public.createuser(plogin text, pchatid bigint, pfirst text, plast text, plocale text) OWNER TO dagaz;

--
-- TOC entry 292 (class 1255 OID 1810143)
-- Name: createuser(text, bigint, bigint, text, text, text); Type: FUNCTION; Schema: public; Owner: dagaz
--

CREATE FUNCTION public.createuser(plogin text, puserid bigint, pchatid bigint, pfirst text, plast text, plocale text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
            declare
               lUser integer;
               lCn integer;
               lCtx integer default null;
            begin
               select max(id), max(context_id) into lUser, lCtx from users where username = pLogin;
               if lCtx is null then
                  insert into common_context default values
                  returning id into lCtx;
               end if;
               if not lUser is null then
                  update users set updated = now(), firstname = pFirst, lastname = pLast, chat_id = pChatId, user_id = pUserId
                  where id = lUser;
               else
                  insert into users (username, firstname, lastname, chat_id, user_id, context_id)
                  values (pLogin, pFirst, pLast, pChatId, pUserId, lCtx)
                  returning id into lUser;
               end if;
               update user_param set created = now(), value = pLocale where user_id = lUser and type_id = 7;
               get diagnostics lCn = row_count;
               if lCn = 0 then
                  insert into user_param(type_id, user_id, value)
                  values (7, lUser, pLocale);
               end if;
               insert into command_queue(context_id, action_id) values (lCtx, 201);
               return lUser;
            end;
            $$;


ALTER FUNCTION public.createuser(plogin text, puserid bigint, pchatid bigint, pfirst text, plast text, plocale text) OWNER TO dagaz;

--
-- TOC entry 275 (class 1255 OID 1810144)
-- Name: enterurl(integer, integer); Type: FUNCTION; Schema: public; Owner: dagaz
--

CREATE FUNCTION public.enterurl(puser integer, pserver integer) RETURNS json
    LANGUAGE plpgsql
    AS $$
          declare
            lToken text default null;
            lUrl text default null;
            r json;
            x record;
          begin
            select value into lToken
            from   user_param
            where  user_id = pUser and type_id = 11;
            select url into lUrl
            from   server
            where  id = pServer;
            for x in
                select lUrl || '/redirect/' || lToken as url,
                  case
                    when lUrl is null or lToken is null then 0
                    else 1
                  end as result
            loop
                r := row_to_json(x);  
            end loop;
            delete from user_param where user_id = pUser and type_id in (2, 3, 11);
            return r;
          end;
          $$;


ALTER FUNCTION public.enterurl(puser integer, pserver integer) OWNER TO dagaz;

--
-- TOC entry 293 (class 1255 OID 1810145)
-- Name: gameurl(integer, integer); Type: FUNCTION; Schema: public; Owner: dagaz
--

CREATE FUNCTION public.gameurl(puser integer, pserver integer) RETURNS json
    LANGUAGE plpgsql
    AS $$
              declare
                lToken text default null;
                lUrl text default null;
                lData text;
                lPlayer text;
                r json;
                x record;
              begin
                select value into lToken from user_param where user_id = pUser and type_id = 11;
                select value into lData from user_param where user_id = pUser and type_id = 8;
                select url into lUrl from server where id = pServer;
                lPlayer := split_part(lData, ',', 2);
                for x in
                    select lUrl || '/redirect/' || lToken || '/' || split_part(lData, ',', 3) || '/' || split_part(lData, ',', 4) as url,
                           lPlayer as player,
                           case
                              when lUrl is null or lToken is null then 0
                              else 1
                           end as result
                loop
                    r := row_to_json(x);  
                end loop;
                delete from user_param where user_id = pUser and type_id in (2, 3, 11);
                return r;
              end;
$$;


ALTER FUNCTION public.gameurl(puser integer, pserver integer) OWNER TO dagaz;

--
-- TOC entry 299 (class 1255 OID 1810146)
-- Name: getcommands(); Type: FUNCTION; Schema: public; Owner: dagaz
--

CREATE FUNCTION public.getcommands() RETURNS integer
    LANGUAGE plpgsql
    AS $$
            declare
              z record;
              t record;
              r integer default 0;
            begin
              for z in
                  select x.id, x.context_id, x.user_id, x.action_id, x.created, x.data
                  from ( select b.id, a.context_id, a.id as user_id, b.created, b.action_id, b.data,
                                row_number() over (partition by b.context_id order by b.created) as rn
                         from   common_context c
                         inner  join users a on (a.context_id = c.id)
                         inner  join command_queue b on (b.context_id = c.id)
                         where  c.action_id is null ) x
                  where  x.rn = 1
                  order  by x.created
              loop
                update common_context set action_id = z.action_id, scheduled = now()
                where  id = z.context_id;
                delete from user_param where user_id = z.user_id 
                and type_id in ( select paramtype_id
                                 from   clear_params
                                 where  coalesce(action_id, z.action_id) = z.action_id);
                if not z.data is null then
                   insert into user_param(type_id, user_id, value)
                   values (8, z.user_id, z.data);
                end if;
                for t in
                    select paramtype_id, value
                    from   command_param
                    where  command_id = z.id
                loop
                    insert into user_param(user_id, type_id, value)
                    values (z.user_id, t.paramtype_id, t.value);
                end loop;
                delete from command_param where command_id = z.id;
                delete from command_queue where id = z.id;
                r := r + 1;
              end loop;
              return r;
            end;
$$;


ALTER FUNCTION public.getcommands() OWNER TO dagaz;

--
-- TOC entry 294 (class 1255 OID 1810147)
-- Name: getnotify(integer, integer); Type: FUNCTION; Schema: public; Owner: dagaz
--

CREATE FUNCTION public.getnotify(pid integer, pserver integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
          declare
            x record;
            z record;
            s text;
            u text;
            c integer;
            lCommand integer;
          begin
            select url into strict u from server where id = pServer;
            for x in
                select id, data->>'user' as username, data->>'sid' as sid, 
                       data->>'url' as url, data->>'opponent' as player
                from   job_data
                where  job_id = pId and result_code = 200 and not data is null
                and    server_id = pServer
                order  by created
            loop
                for z in
                    select y.id as context_id, a.user_id, c.value as pass
                    from   account a
                    inner  join users u on (u.id = a.user_id)
                    inner  join common_context y on (y.id = u.context_id)
                    inner  join user_param b on (b.account_id = a.id and b.type_id = 2)
                    inner  join user_param c on (c.account_id = a.id and c.type_id = 3)
                    where  b.value = x.username and a.deleted is null
                loop
                    s := u || ',' || x.player || ',' || x.url || ',' || x.sid;
                    insert into command_queue(context_id, action_id, data)
                    values (z.context_id, 101, s)
                    returning id into lCommand;
                    insert into command_param(command_id, paramtype_id, value)
                    values(lCommand, 2, x.username);
                    insert into command_param(command_id, paramtype_id, value)
                    values(lCommand, 3, z.pass);
                end loop;
                delete from job_data where id = x.id;
            end loop;
            return 1;
          end;
$$;


ALTER FUNCTION public.getnotify(pid integer, pserver integer) OWNER TO dagaz;

--
-- TOC entry 295 (class 1255 OID 1810148)
-- Name: savemessage(text, bigint, text, bigint); Type: FUNCTION; Schema: public; Owner: dagaz
--

CREATE FUNCTION public.savemessage(plogin text, pid bigint, pdata text, preply bigint) RETURNS json
    LANGUAGE plpgsql
    AS $$
              declare
                z record;
                c integer;
              begin
                for z in
                    select a.id, coalesce(b.value, 'en') as locale
                    from   users a
                    left   join user_param b on (b.user_id = a.id and type_id = 7)
                    where  a.username = pLogin
                loop
                    insert into message(user_id, locale, message_id, data, reply_for)
                    values (z.id, z.locale, pId, pData, pReply);
                    c := c + 1;
                end loop;
                return c;
              end;
$$;


ALTER FUNCTION public.savemessage(plogin text, pid bigint, pdata text, preply bigint) OWNER TO dagaz;

--
-- TOC entry 298 (class 1255 OID 1811067)
-- Name: saveprofile(integer, text, integer); Type: FUNCTION; Schema: public; Owner: lora_server
--

CREATE FUNCTION public.saveprofile(puser integer, paccount text, pserver integer) RETURNS json
    LANGUAGE plpgsql
    AS $$
declare
  lAccount integer;
  r json;
  x record;
begin
  select a.id into strict lAccount
  from   account a
  inner  join user_param b on (b.account_id = a.id and b.type_id = 2)
  where  a.user_id = pUser and a.server_id = pServer and a.deleted is null
  and    pAccount = b.value;
  
  delete from user_param where account_id = lAccount and type_id in (4, 3);
  update user_param set account_id = lAccount, user_id = null where user_id = pUser and type_id = 4;
  update user_param set account_id = lAccount, user_id = null, type_id = 3 where user_id = pUser and type_id = 12;

  for x in
      select 1 as result
  loop
      r := row_to_json(x);  
  end loop;
  return r;
end;
$$;


ALTER FUNCTION public.saveprofile(puser integer, paccount text, pserver integer) OWNER TO lora_server;

--
-- TOC entry 296 (class 1255 OID 1810149)
-- Name: setactionbynum(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: dagaz
--

CREATE FUNCTION public.setactionbynum(puser integer, paction integer, pnum integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
  z record;
  c integer;
  lCtx integer;
begin
  select context_id into strict lCtx 
  from users where id = pUser;
  for z in
      select a.id
      from   action a
      where  a.parent_id = pAction and a.order_num = pNum
  loop
    update common_context set scheduled = now(), updated = now(), action_id = z.id
    where id = lCtx;
    c := c + 1;
  end loop;
  return c;
end;
$$;


ALTER FUNCTION public.setactionbynum(puser integer, paction integer, pnum integer) OWNER TO dagaz;

--
-- TOC entry 289 (class 1255 OID 1810150)
-- Name: setparams(); Type: FUNCTION; Schema: public; Owner: dagaz
--

CREATE FUNCTION public.setparams() RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
  z record;
  q record;
  c integer default 0;
  p integer;
  n integer;
  a integer;
  s timestamp;
begin
  for z in
      select a.id as user_id, b.id, b.paramtype_id, d.message,
             x.id as context_id
      from   users a
      inner  join common_context x on (x.id = a.context_id)
      inner  join action b on (b.id = x.action_id and b.type_id = 5)
      inner  join localized_string d on (d.action_id = b.id and d.locale = 'en')
      where  x.scheduled < now()
      order  by x.scheduled
  loop
      update user_param set created = now(), value = z.message 
      where user_id = z.user_id and type_id = z.paramtype_id;
      get diagnostics n = row_count;
      if n = 0 then
         insert into user_param(type_id, user_id, value)
         values (z.paramtype_id, z.user_id, z.message);
      end if;
      a := null;
      for q in
          select a.script_id, coalesce(a.parent_id, 0) as parent_id, a.order_num
          from   action a
          where  a.id = z.id
      loop
          select max(t.id) into a
          from ( select a.id, row_number() over (order by a.order_num) as rn
                 from   action a
                 where  a.script_id = q.script_id
                 and    coalesce(a.parent_id, 0) = q.parent_id
                 and    a.order_num > q.order_num ) t
          where t.rn = 1;
          if a is null then
             select max(t.id) into a
             from ( select a.id, row_number() over (order by a.order_num) as rn
                    from   action a
                    where  a.script_id = q.script_id
                    and    coalesce(a.parent_id, 0) = z.id ) t
             where t.rn = 1;
          end if;
      end loop;
      s := now();
      if a is null then
         s := null;
      end if;
      update common_context set scheduled = s, updated = now(), action_id = a
      where id = z.context_id;
      c := c + 1;
  end loop;
  return c;
end;
$$;


ALTER FUNCTION public.setparams() OWNER TO dagaz;

--
-- TOC entry 297 (class 1255 OID 1810151)
-- Name: setparamvalue(integer, integer, text); Type: FUNCTION; Schema: public; Owner: dagaz
--

CREATE FUNCTION public.setparamvalue(puser integer, pcode integer, pvalue text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare
  n integer;
begin
  update user_param set created = now(), value = pValue
  where user_id = pUser and type_id = pCode;
  get diagnostics n = row_count;
  if n = 0 then
     insert into user_param(type_id, user_id, value)
     values (pCode, pUser, pValue);
  end if;
  return n;
end;
$$;


ALTER FUNCTION public.setparamvalue(puser integer, pcode integer, pvalue text) OWNER TO dagaz;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- TOC entry 196 (class 1259 OID 1810152)
-- Name: account; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.account (
    id integer NOT NULL,
    server_id integer NOT NULL,
    user_id integer NOT NULL,
    created timestamp without time zone DEFAULT now() NOT NULL,
    deleted timestamp without time zone,
    context_id integer
);


ALTER TABLE public.account OWNER TO dagaz;

--
-- TOC entry 197 (class 1259 OID 1810156)
-- Name: account_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.account_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.account_id_seq OWNER TO dagaz;

--
-- TOC entry 4356 (class 0 OID 0)
-- Dependencies: 197
-- Name: account_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.account_id_seq OWNED BY public.account.id;


--
-- TOC entry 198 (class 1259 OID 1810158)
-- Name: action; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.action (
    id integer NOT NULL,
    type_id integer NOT NULL,
    script_id integer NOT NULL,
    parent_id integer,
    order_num integer NOT NULL,
    follow_to integer,
    paramtype_id integer
);


ALTER TABLE public.action OWNER TO dagaz;

--
-- TOC entry 199 (class 1259 OID 1810161)
-- Name: action_log; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.action_log (
    id integer NOT NULL,
    account_id integer NOT NULL,
    action_id integer NOT NULL,
    event_time timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.action_log OWNER TO dagaz;

--
-- TOC entry 200 (class 1259 OID 1810165)
-- Name: action_log_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.action_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.action_log_id_seq OWNER TO dagaz;

--
-- TOC entry 4357 (class 0 OID 0)
-- Dependencies: 200
-- Name: action_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.action_log_id_seq OWNED BY public.action_log.id;


--
-- TOC entry 201 (class 1259 OID 1810167)
-- Name: action_type; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.action_type (
    id integer NOT NULL,
    name character varying(100) NOT NULL
);


ALTER TABLE public.action_type OWNER TO dagaz;

--
-- TOC entry 270 (class 1259 OID 1813504)
-- Name: clear_params; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.clear_params (
    id integer NOT NULL,
    paramtype_id integer NOT NULL,
    action_id integer
);


ALTER TABLE public.clear_params OWNER TO dagaz;

--
-- TOC entry 202 (class 1259 OID 1810170)
-- Name: client_message; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.client_message (
    id integer NOT NULL,
    parent_id integer NOT NULL,
    message_id bigint NOT NULL
);


ALTER TABLE public.client_message OWNER TO dagaz;

--
-- TOC entry 203 (class 1259 OID 1810173)
-- Name: client_message_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.client_message_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.client_message_id_seq OWNER TO dagaz;

--
-- TOC entry 4358 (class 0 OID 0)
-- Dependencies: 203
-- Name: client_message_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.client_message_id_seq OWNED BY public.client_message.id;


--
-- TOC entry 272 (class 1259 OID 1813570)
-- Name: command_param; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.command_param (
    id integer NOT NULL,
    command_id integer NOT NULL,
    paramtype_id integer NOT NULL,
    value text NOT NULL
);


ALTER TABLE public.command_param OWNER TO dagaz;

--
-- TOC entry 271 (class 1259 OID 1813568)
-- Name: command_param_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.command_param_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.command_param_id_seq OWNER TO dagaz;

--
-- TOC entry 4359 (class 0 OID 0)
-- Dependencies: 271
-- Name: command_param_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.command_param_id_seq OWNED BY public.command_param.id;


--
-- TOC entry 204 (class 1259 OID 1810175)
-- Name: command_queue; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.command_queue (
    id integer NOT NULL,
    context_id integer NOT NULL,
    action_id integer NOT NULL,
    created timestamp without time zone DEFAULT now() NOT NULL,
    data text
);


ALTER TABLE public.command_queue OWNER TO dagaz;

--
-- TOC entry 205 (class 1259 OID 1810182)
-- Name: command_queue_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.command_queue_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.command_queue_id_seq OWNER TO dagaz;

--
-- TOC entry 4360 (class 0 OID 0)
-- Dependencies: 205
-- Name: command_queue_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.command_queue_id_seq OWNED BY public.command_queue.id;


--
-- TOC entry 206 (class 1259 OID 1810184)
-- Name: common_context; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.common_context (
    id integer NOT NULL,
    action_id integer,
    wait_for integer,
    scheduled timestamp without time zone,
    delete_message bigint,
    updated timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.common_context OWNER TO dagaz;

--
-- TOC entry 207 (class 1259 OID 1810188)
-- Name: common_context_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.common_context_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.common_context_id_seq OWNER TO dagaz;

--
-- TOC entry 4361 (class 0 OID 0)
-- Dependencies: 207
-- Name: common_context_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.common_context_id_seq OWNED BY public.common_context.id;


--
-- TOC entry 208 (class 1259 OID 1810190)
-- Name: db_action; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.db_action (
    id integer NOT NULL,
    result_id integer NOT NULL,
    result_value character varying(30) NOT NULL,
    order_num integer NOT NULL,
    action_id integer
);


ALTER TABLE public.db_action OWNER TO dagaz;

--
-- TOC entry 209 (class 1259 OID 1810193)
-- Name: db_param; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.db_param (
    id integer NOT NULL,
    proc_id integer NOT NULL,
    paramtype_id integer,
    value character varying(30),
    order_num integer NOT NULL
);


ALTER TABLE public.db_param OWNER TO dagaz;

--
-- TOC entry 210 (class 1259 OID 1810196)
-- Name: db_result; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.db_result (
    id integer NOT NULL,
    proc_id integer NOT NULL,
    name character varying(30),
    paramtype_id integer
);


ALTER TABLE public.db_result OWNER TO dagaz;

--
-- TOC entry 211 (class 1259 OID 1810199)
-- Name: dbproc; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.dbproc (
    id integer NOT NULL,
    actiontype_id integer,
    name character varying(100) NOT NULL
);


ALTER TABLE public.dbproc OWNER TO dagaz;

--
-- TOC entry 212 (class 1259 OID 1810202)
-- Name: edge; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.edge (
    id integer NOT NULL,
    quest_id integer NOT NULL,
    from_id integer NOT NULL,
    to_id integer NOT NULL,
    en text,
    ru text,
    rule character varying(100),
    max_cnt integer,
    order_num integer NOT NULL
);


ALTER TABLE public.edge OWNER TO dagaz;

--
-- TOC entry 213 (class 1259 OID 1810208)
-- Name: edge_cnt; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.edge_cnt (
    id integer NOT NULL,
    edge_id integer NOT NULL,
    context_id integer NOT NULL,
    max_cnt integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.edge_cnt OWNER TO dagaz;

--
-- TOC entry 214 (class 1259 OID 1810212)
-- Name: edge_cnt_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.edge_cnt_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.edge_cnt_id_seq OWNER TO dagaz;

--
-- TOC entry 4362 (class 0 OID 0)
-- Dependencies: 214
-- Name: edge_cnt_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.edge_cnt_id_seq OWNED BY public.edge_cnt.id;


--
-- TOC entry 215 (class 1259 OID 1810214)
-- Name: edge_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.edge_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.edge_id_seq OWNER TO dagaz;

--
-- TOC entry 4363 (class 0 OID 0)
-- Dependencies: 215
-- Name: edge_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.edge_id_seq OWNED BY public.edge.id;


--
-- TOC entry 216 (class 1259 OID 1810216)
-- Name: edge_info; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.edge_info (
    id integer NOT NULL,
    edge_id integer NOT NULL,
    en text,
    ru text
);


ALTER TABLE public.edge_info OWNER TO dagaz;

--
-- TOC entry 217 (class 1259 OID 1810222)
-- Name: edge_info_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.edge_info_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.edge_info_id_seq OWNER TO dagaz;

--
-- TOC entry 4364 (class 0 OID 0)
-- Dependencies: 217
-- Name: edge_info_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.edge_info_id_seq OWNED BY public.edge_info.id;


--
-- TOC entry 218 (class 1259 OID 1810224)
-- Name: edge_param; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.edge_param (
    id integer NOT NULL,
    edge_id integer NOT NULL,
    param_id integer NOT NULL,
    rule character varying(100)
);


ALTER TABLE public.edge_param OWNER TO dagaz;

--
-- TOC entry 219 (class 1259 OID 1810227)
-- Name: edge_param_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.edge_param_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.edge_param_id_seq OWNER TO dagaz;

--
-- TOC entry 4365 (class 0 OID 0)
-- Dependencies: 219
-- Name: edge_param_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.edge_param_id_seq OWNED BY public.edge_param.id;


--
-- TOC entry 220 (class 1259 OID 1810229)
-- Name: game; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.game (
    id integer NOT NULL,
    parent_id integer,
    name character varying(100) NOT NULL,
    description character varying(1000)
);


ALTER TABLE public.game OWNER TO dagaz;

--
-- TOC entry 221 (class 1259 OID 1810235)
-- Name: info_type; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.info_type (
    id integer NOT NULL,
    name character varying(100) NOT NULL
);


ALTER TABLE public.info_type OWNER TO dagaz;

--
-- TOC entry 222 (class 1259 OID 1810238)
-- Name: job; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.job (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    request_id integer NOT NULL,
    proc_id integer NOT NULL
);


ALTER TABLE public.job OWNER TO dagaz;

--
-- TOC entry 223 (class 1259 OID 1810241)
-- Name: job_data; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.job_data (
    id integer NOT NULL,
    job_id integer NOT NULL,
    result_code integer NOT NULL,
    data json,
    created timestamp without time zone DEFAULT now() NOT NULL,
    server_id integer NOT NULL
);


ALTER TABLE public.job_data OWNER TO dagaz;

--
-- TOC entry 224 (class 1259 OID 1810248)
-- Name: job_data_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.job_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.job_data_id_seq OWNER TO dagaz;

--
-- TOC entry 4366 (class 0 OID 0)
-- Dependencies: 224
-- Name: job_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.job_data_id_seq OWNED BY public.job_data.id;


--
-- TOC entry 225 (class 1259 OID 1810250)
-- Name: localized_string; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.localized_string (
    id integer NOT NULL,
    action_id integer NOT NULL,
    locale character varying(5) NOT NULL,
    message text
);


ALTER TABLE public.localized_string OWNER TO dagaz;

--
-- TOC entry 226 (class 1259 OID 1810256)
-- Name: localized_string_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.localized_string_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.localized_string_id_seq OWNER TO dagaz;

--
-- TOC entry 4367 (class 0 OID 0)
-- Dependencies: 226
-- Name: localized_string_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.localized_string_id_seq OWNED BY public.localized_string.id;


--
-- TOC entry 227 (class 1259 OID 1810264)
-- Name: message; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.message (
    id integer NOT NULL,
    user_id integer NOT NULL,
    send_to integer,
    locale character varying(5) NOT NULL,
    event_time timestamp without time zone DEFAULT now() NOT NULL,
    message_id bigint NOT NULL,
    scheduled timestamp without time zone DEFAULT now(),
    data text NOT NULL,
    sid integer,
    turn integer,
    reply_for bigint
);


ALTER TABLE public.message OWNER TO dagaz;

--
-- TOC entry 228 (class 1259 OID 1810272)
-- Name: message_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.message_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.message_id_seq OWNER TO dagaz;

--
-- TOC entry 4368 (class 0 OID 0)
-- Dependencies: 228
-- Name: message_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.message_id_seq OWNED BY public.message.id;


--
-- TOC entry 229 (class 1259 OID 1810274)
-- Name: migrations; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.migrations (
    id integer NOT NULL,
    "timestamp" bigint NOT NULL,
    name character varying NOT NULL
);


ALTER TABLE public.migrations OWNER TO dagaz;

--
-- TOC entry 230 (class 1259 OID 1810280)
-- Name: migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.migrations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.migrations_id_seq OWNER TO dagaz;

--
-- TOC entry 4369 (class 0 OID 0)
-- Dependencies: 230
-- Name: migrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.migrations_id_seq OWNED BY public.migrations.id;


--
-- TOC entry 231 (class 1259 OID 1810282)
-- Name: node; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.node (
    id integer NOT NULL,
    quest_id integer NOT NULL,
    type_id integer,
    image_id integer
);


ALTER TABLE public.node OWNER TO dagaz;

--
-- TOC entry 232 (class 1259 OID 1810285)
-- Name: node_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.node_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.node_id_seq OWNER TO dagaz;

--
-- TOC entry 4370 (class 0 OID 0)
-- Dependencies: 232
-- Name: node_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.node_id_seq OWNED BY public.node.id;


--
-- TOC entry 233 (class 1259 OID 1810287)
-- Name: node_image; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.node_image (
    id integer NOT NULL,
    filename character varying(1000) NOT NULL
);


ALTER TABLE public.node_image OWNER TO dagaz;

--
-- TOC entry 234 (class 1259 OID 1810293)
-- Name: node_image_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.node_image_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.node_image_id_seq OWNER TO dagaz;

--
-- TOC entry 4371 (class 0 OID 0)
-- Dependencies: 234
-- Name: node_image_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.node_image_id_seq OWNED BY public.node_image.id;


--
-- TOC entry 235 (class 1259 OID 1810295)
-- Name: node_info; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.node_info (
    id integer NOT NULL,
    node_id integer NOT NULL,
    image_id integer,
    en text,
    ru text,
    rule character varying(100),
    order_num integer NOT NULL
);


ALTER TABLE public.node_info OWNER TO dagaz;

--
-- TOC entry 236 (class 1259 OID 1810301)
-- Name: node_info_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.node_info_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.node_info_id_seq OWNER TO dagaz;

--
-- TOC entry 4372 (class 0 OID 0)
-- Dependencies: 236
-- Name: node_info_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.node_info_id_seq OWNED BY public.node_info.id;


--
-- TOC entry 237 (class 1259 OID 1810303)
-- Name: node_type; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.node_type (
    id integer NOT NULL,
    name character varying(100) NOT NULL
);


ALTER TABLE public.node_type OWNER TO dagaz;

--
-- TOC entry 238 (class 1259 OID 1810306)
-- Name: option_type; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.option_type (
    id integer NOT NULL,
    name character varying(100) NOT NULL
);


ALTER TABLE public.option_type OWNER TO dagaz;

--
-- TOC entry 239 (class 1259 OID 1810309)
-- Name: param_type; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.param_type (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    is_hidden boolean DEFAULT false NOT NULL
);


ALTER TABLE public.param_type OWNER TO dagaz;

--
-- TOC entry 240 (class 1259 OID 1810313)
-- Name: quest; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.quest (
    id integer NOT NULL,
    account_id integer,
    en text,
    ru text,
    def_cnt integer
);


ALTER TABLE public.quest OWNER TO dagaz;

--
-- TOC entry 241 (class 1259 OID 1810319)
-- Name: quest_context; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.quest_context (
    id integer NOT NULL,
    action_id integer NOT NULL,
    node_id integer,
    image_id integer
);


ALTER TABLE public.quest_context OWNER TO dagaz;

--
-- TOC entry 242 (class 1259 OID 1810322)
-- Name: quest_context_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.quest_context_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.quest_context_id_seq OWNER TO dagaz;

--
-- TOC entry 4373 (class 0 OID 0)
-- Dependencies: 242
-- Name: quest_context_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.quest_context_id_seq OWNED BY public.quest_context.id;


--
-- TOC entry 243 (class 1259 OID 1810324)
-- Name: quest_grant; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.quest_grant (
    id integer NOT NULL,
    quest_id integer NOT NULL,
    grantor_id integer NOT NULL,
    grant_to integer,
    created timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.quest_grant OWNER TO dagaz;

--
-- TOC entry 244 (class 1259 OID 1810328)
-- Name: quest_grant_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.quest_grant_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.quest_grant_id_seq OWNER TO dagaz;

--
-- TOC entry 4374 (class 0 OID 0)
-- Dependencies: 244
-- Name: quest_grant_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.quest_grant_id_seq OWNED BY public.quest_grant.id;


--
-- TOC entry 245 (class 1259 OID 1810330)
-- Name: quest_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.quest_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.quest_id_seq OWNER TO dagaz;

--
-- TOC entry 4375 (class 0 OID 0)
-- Dependencies: 245
-- Name: quest_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.quest_id_seq OWNED BY public.quest.id;


--
-- TOC entry 246 (class 1259 OID 1810332)
-- Name: quest_info; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.quest_info (
    id integer NOT NULL,
    quest_id integer NOT NULL,
    type_id integer NOT NULL,
    en text,
    ru text
);


ALTER TABLE public.quest_info OWNER TO dagaz;

--
-- TOC entry 247 (class 1259 OID 1810338)
-- Name: quest_info_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.quest_info_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.quest_info_id_seq OWNER TO dagaz;

--
-- TOC entry 4376 (class 0 OID 0)
-- Dependencies: 247
-- Name: quest_info_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.quest_info_id_seq OWNED BY public.quest_info.id;


--
-- TOC entry 248 (class 1259 OID 1810340)
-- Name: quest_param; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.quest_param (
    id integer NOT NULL,
    quest_id integer NOT NULL,
    name text NOT NULL,
    order_num integer NOT NULL
);


ALTER TABLE public.quest_param OWNER TO dagaz;

--
-- TOC entry 249 (class 1259 OID 1810346)
-- Name: quest_param_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.quest_param_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.quest_param_id_seq OWNER TO dagaz;

--
-- TOC entry 4377 (class 0 OID 0)
-- Dependencies: 249
-- Name: quest_param_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.quest_param_id_seq OWNED BY public.quest_param.id;


--
-- TOC entry 250 (class 1259 OID 1810348)
-- Name: quest_stat; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.quest_stat (
    id integer NOT NULL,
    account_id integer NOT NULL,
    quest_id integer NOT NULL,
    "all" integer DEFAULT 0 NOT NULL,
    win integer DEFAULT 0 NOT NULL,
    bonus integer DEFAULT 0 NOT NULL,
    created timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.quest_stat OWNER TO dagaz;

--
-- TOC entry 251 (class 1259 OID 1810355)
-- Name: quest_stat_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.quest_stat_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.quest_stat_id_seq OWNER TO dagaz;

--
-- TOC entry 4378 (class 0 OID 0)
-- Dependencies: 251
-- Name: quest_stat_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.quest_stat_id_seq OWNED BY public.quest_stat.id;


--
-- TOC entry 252 (class 1259 OID 1810357)
-- Name: quest_subs; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.quest_subs (
    id integer NOT NULL,
    quest_id integer NOT NULL,
    from_str character varying(100) NOT NULL,
    to_str character varying(100) NOT NULL
);


ALTER TABLE public.quest_subs OWNER TO dagaz;

--
-- TOC entry 253 (class 1259 OID 1810360)
-- Name: quest_subs_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.quest_subs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.quest_subs_id_seq OWNER TO dagaz;

--
-- TOC entry 4379 (class 0 OID 0)
-- Dependencies: 253
-- Name: quest_subs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.quest_subs_id_seq OWNED BY public.quest_subs.id;


--
-- TOC entry 254 (class 1259 OID 1810362)
-- Name: request; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.request (
    id integer NOT NULL,
    server_id integer NOT NULL,
    request_type character varying(10) NOT NULL,
    url character varying(100) NOT NULL,
    actiontype_id integer
);


ALTER TABLE public.request OWNER TO dagaz;

--
-- TOC entry 255 (class 1259 OID 1810365)
-- Name: request_param; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.request_param (
    id integer NOT NULL,
    request_id integer NOT NULL,
    paramtype_id integer,
    param_name character varying(30),
    param_value character varying(30)
);


ALTER TABLE public.request_param OWNER TO dagaz;

--
-- TOC entry 256 (class 1259 OID 1810368)
-- Name: response; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.response (
    id integer NOT NULL,
    request_id integer NOT NULL,
    result_code integer NOT NULL,
    order_num integer NOT NULL,
    action_id integer
);


ALTER TABLE public.response OWNER TO dagaz;

--
-- TOC entry 257 (class 1259 OID 1810371)
-- Name: response_param; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.response_param (
    id integer NOT NULL,
    response_id integer NOT NULL,
    paramtype_id integer,
    param_name character varying(30)
);


ALTER TABLE public.response_param OWNER TO dagaz;

--
-- TOC entry 258 (class 1259 OID 1810374)
-- Name: script; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.script (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    command character varying(10)
);


ALTER TABLE public.script OWNER TO dagaz;

--
-- TOC entry 259 (class 1259 OID 1810377)
-- Name: script_param; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.script_param (
    id integer NOT NULL,
    script_id integer NOT NULL,
    paramtype_id integer,
    order_num integer NOT NULL
);


ALTER TABLE public.script_param OWNER TO dagaz;

--
-- TOC entry 260 (class 1259 OID 1810380)
-- Name: server; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.server (
    id integer NOT NULL,
    type_id integer NOT NULL,
    url text,
    api text
);


ALTER TABLE public.server OWNER TO dagaz;

--
-- TOC entry 261 (class 1259 OID 1810386)
-- Name: server_option; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.server_option (
    id integer NOT NULL,
    type_id integer NOT NULL,
    server_id integer NOT NULL,
    value text NOT NULL
);


ALTER TABLE public.server_option OWNER TO dagaz;

--
-- TOC entry 262 (class 1259 OID 1810392)
-- Name: server_type; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.server_type (
    id integer NOT NULL,
    name character varying(100) NOT NULL
);


ALTER TABLE public.server_type OWNER TO dagaz;

--
-- TOC entry 263 (class 1259 OID 1810395)
-- Name: user_param; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.user_param (
    id integer NOT NULL,
    type_id integer NOT NULL,
    user_id integer,
    value text NOT NULL,
    created timestamp without time zone DEFAULT now() NOT NULL,
    account_id integer
);


ALTER TABLE public.user_param OWNER TO dagaz;

--
-- TOC entry 264 (class 1259 OID 1810402)
-- Name: user_param_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.user_param_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.user_param_id_seq OWNER TO dagaz;

--
-- TOC entry 4380 (class 0 OID 0)
-- Dependencies: 264
-- Name: user_param_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.user_param_id_seq OWNED BY public.user_param.id;


--
-- TOC entry 265 (class 1259 OID 1810404)
-- Name: users; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.users (
    id integer NOT NULL,
    username character varying(100) NOT NULL,
    firstname character varying(100) NOT NULL,
    created timestamp without time zone DEFAULT now() NOT NULL,
    updated timestamp without time zone DEFAULT now() NOT NULL,
    lastname character varying(100),
    chat_id bigint NOT NULL,
    is_admin boolean DEFAULT false NOT NULL,
    context_id integer,
    user_id bigint
);


ALTER TABLE public.users OWNER TO dagaz;

--
-- TOC entry 266 (class 1259 OID 1810410)
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_id_seq OWNER TO dagaz;

--
-- TOC entry 4381 (class 0 OID 0)
-- Dependencies: 266
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- TOC entry 267 (class 1259 OID 1810412)
-- Name: watch; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.watch (
    id integer NOT NULL,
    user_id integer NOT NULL,
    server_id integer NOT NULL,
    type_id integer NOT NULL,
    parent_id integer,
    value character varying(100) NOT NULL
);


ALTER TABLE public.watch OWNER TO dagaz;

--
-- TOC entry 268 (class 1259 OID 1810415)
-- Name: watch_id_seq; Type: SEQUENCE; Schema: public; Owner: dagaz
--

CREATE SEQUENCE public.watch_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.watch_id_seq OWNER TO dagaz;

--
-- TOC entry 4382 (class 0 OID 0)
-- Dependencies: 268
-- Name: watch_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: dagaz
--

ALTER SEQUENCE public.watch_id_seq OWNED BY public.watch.id;


--
-- TOC entry 269 (class 1259 OID 1810417)
-- Name: watch_type; Type: TABLE; Schema: public; Owner: dagaz
--

CREATE TABLE public.watch_type (
    id integer NOT NULL,
    name character varying(100) NOT NULL
);


ALTER TABLE public.watch_type OWNER TO dagaz;

--
-- TOC entry 3833 (class 2604 OID 1810420)
-- Name: account id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.account ALTER COLUMN id SET DEFAULT nextval('public.account_id_seq'::regclass);


--
-- TOC entry 3835 (class 2604 OID 1810421)
-- Name: action_log id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.action_log ALTER COLUMN id SET DEFAULT nextval('public.action_log_id_seq'::regclass);


--
-- TOC entry 3836 (class 2604 OID 1810422)
-- Name: client_message id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.client_message ALTER COLUMN id SET DEFAULT nextval('public.client_message_id_seq'::regclass);


--
-- TOC entry 3876 (class 2604 OID 1813573)
-- Name: command_param id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.command_param ALTER COLUMN id SET DEFAULT nextval('public.command_param_id_seq'::regclass);


--
-- TOC entry 3838 (class 2604 OID 1810423)
-- Name: command_queue id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.command_queue ALTER COLUMN id SET DEFAULT nextval('public.command_queue_id_seq'::regclass);


--
-- TOC entry 3840 (class 2604 OID 1810424)
-- Name: common_context id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.common_context ALTER COLUMN id SET DEFAULT nextval('public.common_context_id_seq'::regclass);


--
-- TOC entry 3841 (class 2604 OID 1810425)
-- Name: edge id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.edge ALTER COLUMN id SET DEFAULT nextval('public.edge_id_seq'::regclass);


--
-- TOC entry 3843 (class 2604 OID 1810426)
-- Name: edge_cnt id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.edge_cnt ALTER COLUMN id SET DEFAULT nextval('public.edge_cnt_id_seq'::regclass);


--
-- TOC entry 3844 (class 2604 OID 1810427)
-- Name: edge_info id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.edge_info ALTER COLUMN id SET DEFAULT nextval('public.edge_info_id_seq'::regclass);


--
-- TOC entry 3845 (class 2604 OID 1810428)
-- Name: edge_param id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.edge_param ALTER COLUMN id SET DEFAULT nextval('public.edge_param_id_seq'::regclass);


--
-- TOC entry 3847 (class 2604 OID 1810429)
-- Name: job_data id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.job_data ALTER COLUMN id SET DEFAULT nextval('public.job_data_id_seq'::regclass);


--
-- TOC entry 3848 (class 2604 OID 1810430)
-- Name: localized_string id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.localized_string ALTER COLUMN id SET DEFAULT nextval('public.localized_string_id_seq'::regclass);


--
-- TOC entry 3851 (class 2604 OID 1810431)
-- Name: message id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.message ALTER COLUMN id SET DEFAULT nextval('public.message_id_seq'::regclass);


--
-- TOC entry 3852 (class 2604 OID 1810432)
-- Name: migrations id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.migrations ALTER COLUMN id SET DEFAULT nextval('public.migrations_id_seq'::regclass);


--
-- TOC entry 3853 (class 2604 OID 1810433)
-- Name: node id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.node ALTER COLUMN id SET DEFAULT nextval('public.node_id_seq'::regclass);


--
-- TOC entry 3854 (class 2604 OID 1810434)
-- Name: node_image id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.node_image ALTER COLUMN id SET DEFAULT nextval('public.node_image_id_seq'::regclass);


--
-- TOC entry 3855 (class 2604 OID 1810435)
-- Name: node_info id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.node_info ALTER COLUMN id SET DEFAULT nextval('public.node_info_id_seq'::regclass);


--
-- TOC entry 3857 (class 2604 OID 1810436)
-- Name: quest id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest ALTER COLUMN id SET DEFAULT nextval('public.quest_id_seq'::regclass);


--
-- TOC entry 3858 (class 2604 OID 1810437)
-- Name: quest_context id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_context ALTER COLUMN id SET DEFAULT nextval('public.quest_context_id_seq'::regclass);


--
-- TOC entry 3860 (class 2604 OID 1810438)
-- Name: quest_grant id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_grant ALTER COLUMN id SET DEFAULT nextval('public.quest_grant_id_seq'::regclass);


--
-- TOC entry 3861 (class 2604 OID 1810439)
-- Name: quest_info id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_info ALTER COLUMN id SET DEFAULT nextval('public.quest_info_id_seq'::regclass);


--
-- TOC entry 3862 (class 2604 OID 1810440)
-- Name: quest_param id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_param ALTER COLUMN id SET DEFAULT nextval('public.quest_param_id_seq'::regclass);


--
-- TOC entry 3867 (class 2604 OID 1810441)
-- Name: quest_stat id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_stat ALTER COLUMN id SET DEFAULT nextval('public.quest_stat_id_seq'::regclass);


--
-- TOC entry 3868 (class 2604 OID 1810442)
-- Name: quest_subs id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_subs ALTER COLUMN id SET DEFAULT nextval('public.quest_subs_id_seq'::regclass);


--
-- TOC entry 3870 (class 2604 OID 1810443)
-- Name: user_param id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.user_param ALTER COLUMN id SET DEFAULT nextval('public.user_param_id_seq'::regclass);


--
-- TOC entry 3874 (class 2604 OID 1810444)
-- Name: users id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- TOC entry 3875 (class 2604 OID 1810445)
-- Name: watch id; Type: DEFAULT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.watch ALTER COLUMN id SET DEFAULT nextval('public.watch_id_seq'::regclass);


--
-- TOC entry 4274 (class 0 OID 1810152)
-- Dependencies: 196
-- Data for Name: account; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.account (id, server_id, user_id, created, deleted, context_id) FROM stdin;
\.


--
-- TOC entry 4276 (class 0 OID 1810158)
-- Dependencies: 198
-- Data for Name: action; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.action (id, type_id, script_id, parent_id, order_num, follow_to, paramtype_id) FROM stdin;
201	3	2	\N	1	\N	\N
202	4	2	201	1	\N	\N
203	4	2	201	2	\N	\N
204	2	2	202	1	\N	2
206	2	2	202	3	\N	4
207	10	2	202	4	\N	\N
208	12	2	207	1	\N	5
211	2	2	203	1	\N	2
212	2	2	203	2	\N	3
213	11	2	203	3	\N	\N
214	12	2	213	1	\N	5
301	5	3	\N	1	\N	7
302	1	3	\N	2	\N	\N
401	5	4	\N	1	\N	7
402	1	4	\N	2	\N	\N
210	1	2	207	2	201	\N
216	1	2	213	2	201	\N
205	2	2	202	2	\N	3
501	14	5	\N	1	\N	\N
502	1	5	501	1	201	\N
503	15	5	501	2	\N	11
504	16	5	503	1	\N	\N
505	6	5	501	3	501	2
101	15	1	\N	1	\N	11
506	1	5	504	2	\N	\N
103	1	1	102	1	\N	\N
102	17	1	101	1	\N	\N
217	1	2	208	1	\N	\N
218	1	2	214	1	\N	\N
601	18	6	\N	1	\N	\N
610	1	6	601	1	201	\N
620	2	6	601	2	\N	9
621	2	6	620	1	\N	12
622	2	6	620	2	\N	4
623	19	6	620	3	\N	\N
624	20	6	623	1	\N	\N
625	1	6	624	1	\N	\N
626	1	6	623	2	\N	\N
630	6	6	601	3	601	2
701	3	7	\N	1	\N	\N
702	5	7	701	1	\N	7
703	1	7	702	1	\N	\N
704	5	7	701	2	\N	7
705	1	7	704	1	\N	\N
\.


--
-- TOC entry 4277 (class 0 OID 1810161)
-- Dependencies: 199
-- Data for Name: action_log; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.action_log (id, account_id, action_id, event_time) FROM stdin;
\.


--
-- TOC entry 4279 (class 0 OID 1810167)
-- Dependencies: 201
-- Data for Name: action_type; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.action_type (id, name) FROM stdin;
1	Вывод текста
2	Ввод текста
3	Меню
4	Пункт меню
10	Создать учётную запись на DagazServer
11	Авторизоваться на DagazServer
12	Связать пользователя с учётной записью
13	Перейти к игре
5	Изменение переменной
14	Проверить username
6	Динамическое меню
15	Запросить тикет
16	Получить url для входа на сервер
17	Получить url для входа в игру
18	Выбрать учётную запись
19	Внести изменения в профиль
20	Сохранить изменения профиля
\.


--
-- TOC entry 4348 (class 0 OID 1813504)
-- Dependencies: 270
-- Data for Name: clear_params; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.clear_params (id, paramtype_id, action_id) FROM stdin;
1	8	\N
2	2	\N
3	3	\N
4	4	\N
5	5	\N
6	6	\N
7	9	\N
8	11	\N
9	12	\N
\.


--
-- TOC entry 4280 (class 0 OID 1810170)
-- Dependencies: 202
-- Data for Name: client_message; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.client_message (id, parent_id, message_id) FROM stdin;
\.


--
-- TOC entry 4350 (class 0 OID 1813570)
-- Dependencies: 272
-- Data for Name: command_param; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.command_param (id, command_id, paramtype_id, value) FROM stdin;
\.


--
-- TOC entry 4282 (class 0 OID 1810175)
-- Dependencies: 204
-- Data for Name: command_queue; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.command_queue (id, context_id, action_id, created, data) FROM stdin;
\.


--
-- TOC entry 4284 (class 0 OID 1810184)
-- Dependencies: 206
-- Data for Name: common_context; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.common_context (id, action_id, wait_for, scheduled, delete_message, updated) FROM stdin;
\.


--
-- TOC entry 4286 (class 0 OID 1810190)
-- Dependencies: 208
-- Data for Name: db_action; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.db_action (id, result_id, result_value, order_num, action_id) FROM stdin;
1	1	0	1	502
2	1	1	2	503
3	1	2	3	505
4	4	1	1	506
5	8	1	1	103
6	9	1	1	217
7	10	0	1	610
8	10	1	2	620
9	10	2	3	630
10	13	1	1	625
\.


--
-- TOC entry 4287 (class 0 OID 1810193)
-- Dependencies: 209
-- Data for Name: db_param; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.db_param (id, proc_id, paramtype_id, value, order_num) FROM stdin;
2	2	2	\N	2
4	3	\N	2	2
1	1	\N	2	2
3	2	\N	2	3
5	5	\N	2	2
6	6	2	\N	2
7	6	\N	2	3
8	7	2	\N	2
9	7	\N	2	3
\.


--
-- TOC entry 4288 (class 0 OID 1810196)
-- Dependencies: 210
-- Data for Name: db_result; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.db_result (id, proc_id, name, paramtype_id) FROM stdin;
1	2	result	\N
2	2	login	2
3	2	password	3
4	3	result	\N
5	3	url	11
6	5	url	11
7	5	player	9
8	5	result	\N
9	1	result	\N
10	6	result	\N
11	6	login	2
12	6	password	3
13	7	result	\N
\.


--
-- TOC entry 4289 (class 0 OID 1810199)
-- Dependencies: 211
-- Data for Name: dbproc; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.dbproc (id, actiontype_id, name) FROM stdin;
1	12	createAccount
2	14	chooseAccount
3	16	enterUrl
4	\N	getNotify
5	17	gameUrl
6	18	chooseAccount
7	20	saveProfile
\.


--
-- TOC entry 4290 (class 0 OID 1810202)
-- Dependencies: 212
-- Data for Name: edge; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.edge (id, quest_id, from_id, to_id, en, ru, rule, max_cnt, order_num) FROM stdin;
\.


--
-- TOC entry 4291 (class 0 OID 1810208)
-- Dependencies: 213
-- Data for Name: edge_cnt; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.edge_cnt (id, edge_id, context_id, max_cnt) FROM stdin;
\.


--
-- TOC entry 4294 (class 0 OID 1810216)
-- Dependencies: 216
-- Data for Name: edge_info; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.edge_info (id, edge_id, en, ru) FROM stdin;
\.


--
-- TOC entry 4296 (class 0 OID 1810224)
-- Dependencies: 218
-- Data for Name: edge_param; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.edge_param (id, edge_id, param_id, rule) FROM stdin;
\.


--
-- TOC entry 4298 (class 0 OID 1810229)
-- Dependencies: 220
-- Data for Name: game; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.game (id, parent_id, name, description) FROM stdin;
\.


--
-- TOC entry 4299 (class 0 OID 1810235)
-- Dependencies: 221
-- Data for Name: info_type; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.info_type (id, name) FROM stdin;
1	Текст задания
2	Текст поздравления
\.


--
-- TOC entry 4300 (class 0 OID 1810238)
-- Dependencies: 222
-- Data for Name: job; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.job (id, name, request_id, proc_id) FROM stdin;
1	notify	3	4
\.


--
-- TOC entry 4301 (class 0 OID 1810241)
-- Dependencies: 223
-- Data for Name: job_data; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.job_data (id, job_id, result_code, data, created, server_id) FROM stdin;
\.


--
-- TOC entry 4303 (class 0 OID 1810250)
-- Dependencies: 225
-- Data for Name: localized_string; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.localized_string (id, action_id, locale, message) FROM stdin;
1	201	ru	Выберите действие для регистрации на DagazServer
2	201	en	Choose an action to register on the DagazServer
3	202	ru	Создать учётную запись
4	202	en	Create an account
5	203	ru	Подключить учётную запись
6	203	en	Connect your account
7	204	ru	Введите логин:
8	204	en	Enter Login:
14	210	ru	Учётная запись с таким именем уже существует
15	210	en	An account with the same name already exists
16	211	ru	Введите логин:
17	211	en	Enter Login:
18	212	ru	Введите пароль:
19	212	en	Enter Password:
22	216	ru	Неверный логин или пароль
23	216	en	Wrong login or password
28	301	en	en
29	302	en	Language configured: English
30	401	en	ru
31	402	ru	Язык сконфигурирован: Русский
32	205	en	Enter Password:
33	205	ru	Введите пароль:
10	206	ru	Введите EMail:
11	206	en	Enter EMail:
34	502	ru	Учётная запись не найдена
35	502	en	Account not found
38	505	ru	Выберите учётную запись
39	505	en	Choose an account
36	506	ru	Перейдите по ссылке на DagazServer: {LINK}
37	506	en	Follow the link to DagazServer: {LINK}
40	103	ru	Пользователь [{PLAYER}] ожидает вашего хода: {LINK}
41	103	en	User [{PLAYER}] awaits your move: {LINK}'
42	217	ru	Соединение с DagazServer успешно установлено
43	217	en	Relation to DagazServer successfully established
44	218	ru	Соединение с DagazServer успешно установлено
45	218	en	Relation to DagazServer successfully established
46	610	ru	Учётная запись не найдена
47	610	en	Account not found
48	620	ru	Введите имя:
49	620	en	Enter your name:
50	621	ru	Введите пароль:
51	621	en	Enter Password:
52	622	ru	Введите EMail:
53	622	en	Enter EMail:
54	624	ru	Changes successfully saved
55	624	en	Изменения учпешно сохранены
56	626	ru	Failed to save changes
57	626	en	Не удалось сохранить изменения
58	630	ru	Выберите учётную запись
59	630	en	Choose an account
60	625	en	Changes successfully saved
61	625	ru	Изменения учпешно сохранены
62	701	ru	Выберите язык
63	701	en	Choose an language
64	702	ru	en
65	702	en	en
66	703	en	Language configured: English
67	704	ru	ru
68	704	en	ru
69	705	ru	Язык сконфигурирован: Русский
\.


--
-- TOC entry 4305 (class 0 OID 1810264)
-- Dependencies: 227
-- Data for Name: message; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.message (id, user_id, send_to, locale, event_time, message_id, scheduled, data, sid, turn, reply_for) FROM stdin;
\.


--
-- TOC entry 4307 (class 0 OID 1810274)
-- Dependencies: 229
-- Data for Name: migrations; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.migrations (id, "timestamp", name) FROM stdin;
16	1693392897178	init1693392897178
17	1699867902762	scripts1699867902762
18	1701330484301	dbproc1701330484301
19	1702892899050	tgq1702892899050
\.


--
-- TOC entry 4309 (class 0 OID 1810282)
-- Dependencies: 231
-- Data for Name: node; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.node (id, quest_id, type_id, image_id) FROM stdin;
\.


--
-- TOC entry 4311 (class 0 OID 1810287)
-- Dependencies: 233
-- Data for Name: node_image; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.node_image (id, filename) FROM stdin;
\.


--
-- TOC entry 4313 (class 0 OID 1810295)
-- Dependencies: 235
-- Data for Name: node_info; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.node_info (id, node_id, image_id, en, ru, rule, order_num) FROM stdin;
\.


--
-- TOC entry 4315 (class 0 OID 1810303)
-- Dependencies: 237
-- Data for Name: node_type; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.node_type (id, name) FROM stdin;
1	Стартовая локация
2	Финальная локация
3	Провальная локация
4	Пустая локация
\.


--
-- TOC entry 4316 (class 0 OID 1810306)
-- Dependencies: 238
-- Data for Name: option_type; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.option_type (id, name) FROM stdin;
1	TOKEN
\.


--
-- TOC entry 4317 (class 0 OID 1810309)
-- Dependencies: 239
-- Data for Name: param_type; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.param_type (id, name, is_hidden) FROM stdin;
1	Токен	f
2	Логин	f
4	EMail	f
5	URL	f
6	SID	f
7	LOCALE	f
11	LINK	f
3	Пароль	t
8	DATA	f
9	PLAYER	f
12	Новый пароль	t
\.


--
-- TOC entry 4318 (class 0 OID 1810313)
-- Dependencies: 240
-- Data for Name: quest; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.quest (id, account_id, en, ru, def_cnt) FROM stdin;
\.


--
-- TOC entry 4319 (class 0 OID 1810319)
-- Dependencies: 241
-- Data for Name: quest_context; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.quest_context (id, action_id, node_id, image_id) FROM stdin;
\.


--
-- TOC entry 4321 (class 0 OID 1810324)
-- Dependencies: 243
-- Data for Name: quest_grant; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.quest_grant (id, quest_id, grantor_id, grant_to, created) FROM stdin;
\.


--
-- TOC entry 4324 (class 0 OID 1810332)
-- Dependencies: 246
-- Data for Name: quest_info; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.quest_info (id, quest_id, type_id, en, ru) FROM stdin;
\.


--
-- TOC entry 4326 (class 0 OID 1810340)
-- Dependencies: 248
-- Data for Name: quest_param; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.quest_param (id, quest_id, name, order_num) FROM stdin;
\.


--
-- TOC entry 4328 (class 0 OID 1810348)
-- Dependencies: 250
-- Data for Name: quest_stat; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.quest_stat (id, account_id, quest_id, "all", win, bonus, created) FROM stdin;
\.


--
-- TOC entry 4330 (class 0 OID 1810357)
-- Dependencies: 252
-- Data for Name: quest_subs; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.quest_subs (id, quest_id, from_str, to_str) FROM stdin;
\.


--
-- TOC entry 4332 (class 0 OID 1810362)
-- Dependencies: 254
-- Data for Name: request; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.request (id, server_id, request_type, url, actiontype_id) FROM stdin;
3	2	GET	/session/notify	\N
1	2	POST	/auth/user	10
2	2	POST	/auth/login	11
4	2	POST	/auth/ticket	15
5	2	POST	/users/edit	19
\.


--
-- TOC entry 4333 (class 0 OID 1810365)
-- Dependencies: 255
-- Data for Name: request_param; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.request_param (id, request_id, paramtype_id, param_name, param_value) FROM stdin;
1	1	2	name	\N
2	1	2	username	\N
4	1	4	email	\N
5	2	2	username	\N
6	2	3	password	\N
3	1	3	password	\N
7	1	\N	device	telegram
8	2	\N	device	telegram
9	4	2	username	\N
10	4	3	password	\N
11	5	9	name	\N
12	5	2	username	\N
13	5	3	password	\N
14	5	4	email	\N
15	5	12	newpass	\N
\.


--
-- TOC entry 4334 (class 0 OID 1810368)
-- Dependencies: 256
-- Data for Name: response; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.response (id, request_id, result_code, order_num, action_id) FROM stdin;
4	2	401	2	\N
5	3	200	1	\N
2	1	400	2	\N
1	1	200	1	\N
3	2	201	1	\N
6	4	200	1	\N
7	5	200	1	\N
8	5	404	2	\N
\.


--
-- TOC entry 4335 (class 0 OID 1810371)
-- Dependencies: 257
-- Data for Name: response_param; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.response_param (id, response_id, paramtype_id, param_name) FROM stdin;
1	1	1	access_token
2	3	1	access_token
3	5	6	sid
4	6	11	ticket
\.


--
-- TOC entry 4336 (class 0 OID 1810374)
-- Dependencies: 258
-- Data for Name: script; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.script (id, name, command) FROM stdin;
1	Уведомление об ожидании хода	\N
5	Enter to Dagaz	enter
2	Account registration	start
6	Edit profile	edit
7	Change Language	lang
3	English	\N
4	Russian	\N
\.


--
-- TOC entry 4337 (class 0 OID 1810377)
-- Dependencies: 259
-- Data for Name: script_param; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.script_param (id, script_id, paramtype_id, order_num) FROM stdin;
1	5	2	1
2	6	2	1
\.


--
-- TOC entry 4338 (class 0 OID 1810380)
-- Dependencies: 260
-- Data for Name: server; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.server (id, type_id, url, api) FROM stdin;
1	1	\N	\N
2	2	https://games.dtco.ru	https://games.dtco.ru/api
\.


--
-- TOC entry 4339 (class 0 OID 1810386)
-- Dependencies: 261
-- Data for Name: server_option; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.server_option (id, type_id, server_id, value) FROM stdin;
1	1	1	XXXXXXXXXX:XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
\.


--
-- TOC entry 4340 (class 0 OID 1810392)
-- Dependencies: 262
-- Data for Name: server_type; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.server_type (id, name) FROM stdin;
1	Telegram
2	Dagaz Server
\.


--
-- TOC entry 4341 (class 0 OID 1810395)
-- Dependencies: 263
-- Data for Name: user_param; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.user_param (id, type_id, user_id, value, created, account_id) FROM stdin;
\.


--
-- TOC entry 4343 (class 0 OID 1810404)
-- Dependencies: 265
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.users (id, username, firstname, created, updated, lastname, chat_id, is_admin, context_id, user_id) FROM stdin;
\.


--
-- TOC entry 4345 (class 0 OID 1810412)
-- Dependencies: 267
-- Data for Name: watch; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.watch (id, user_id, server_id, type_id, parent_id, value) FROM stdin;
\.


--
-- TOC entry 4347 (class 0 OID 1810417)
-- Dependencies: 269
-- Data for Name: watch_type; Type: TABLE DATA; Schema: public; Owner: dagaz
--

COPY public.watch_type (id, name) FROM stdin;
1	Следить за игрой
2	Следить за игроком
3	Не следить за игрой
4	Не следить за игроком
\.


--
-- TOC entry 4383 (class 0 OID 0)
-- Dependencies: 197
-- Name: account_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.account_id_seq', 382, true);


--
-- TOC entry 4384 (class 0 OID 0)
-- Dependencies: 200
-- Name: action_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.action_log_id_seq', 1, false);


--
-- TOC entry 4385 (class 0 OID 0)
-- Dependencies: 203
-- Name: client_message_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.client_message_id_seq', 64, true);


--
-- TOC entry 4386 (class 0 OID 0)
-- Dependencies: 271
-- Name: command_param_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.command_param_id_seq', 4, true);


--
-- TOC entry 4387 (class 0 OID 0)
-- Dependencies: 205
-- Name: command_queue_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.command_queue_id_seq', 217, true);


--
-- TOC entry 4388 (class 0 OID 0)
-- Dependencies: 207
-- Name: common_context_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.common_context_id_seq', 21, true);


--
-- TOC entry 4389 (class 0 OID 0)
-- Dependencies: 214
-- Name: edge_cnt_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.edge_cnt_id_seq', 1, false);


--
-- TOC entry 4390 (class 0 OID 0)
-- Dependencies: 215
-- Name: edge_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.edge_id_seq', 1, false);


--
-- TOC entry 4391 (class 0 OID 0)
-- Dependencies: 217
-- Name: edge_info_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.edge_info_id_seq', 1, false);


--
-- TOC entry 4392 (class 0 OID 0)
-- Dependencies: 219
-- Name: edge_param_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.edge_param_id_seq', 1, false);


--
-- TOC entry 4393 (class 0 OID 0)
-- Dependencies: 224
-- Name: job_data_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.job_data_id_seq', 22, true);


--
-- TOC entry 4394 (class 0 OID 0)
-- Dependencies: 226
-- Name: localized_string_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.localized_string_id_seq', 69, true);


--
-- TOC entry 4395 (class 0 OID 0)
-- Dependencies: 228
-- Name: message_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.message_id_seq', 41, true);


--
-- TOC entry 4396 (class 0 OID 0)
-- Dependencies: 230
-- Name: migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.migrations_id_seq', 19, true);


--
-- TOC entry 4397 (class 0 OID 0)
-- Dependencies: 232
-- Name: node_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.node_id_seq', 1, false);


--
-- TOC entry 4398 (class 0 OID 0)
-- Dependencies: 234
-- Name: node_image_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.node_image_id_seq', 1, false);


--
-- TOC entry 4399 (class 0 OID 0)
-- Dependencies: 236
-- Name: node_info_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.node_info_id_seq', 1, false);


--
-- TOC entry 4400 (class 0 OID 0)
-- Dependencies: 242
-- Name: quest_context_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.quest_context_id_seq', 1, false);


--
-- TOC entry 4401 (class 0 OID 0)
-- Dependencies: 244
-- Name: quest_grant_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.quest_grant_id_seq', 1, false);


--
-- TOC entry 4402 (class 0 OID 0)
-- Dependencies: 245
-- Name: quest_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.quest_id_seq', 1, false);


--
-- TOC entry 4403 (class 0 OID 0)
-- Dependencies: 247
-- Name: quest_info_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.quest_info_id_seq', 1, false);


--
-- TOC entry 4404 (class 0 OID 0)
-- Dependencies: 249
-- Name: quest_param_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.quest_param_id_seq', 1, false);


--
-- TOC entry 4405 (class 0 OID 0)
-- Dependencies: 251
-- Name: quest_stat_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.quest_stat_id_seq', 1, false);


--
-- TOC entry 4406 (class 0 OID 0)
-- Dependencies: 253
-- Name: quest_subs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.quest_subs_id_seq', 1, false);


--
-- TOC entry 4407 (class 0 OID 0)
-- Dependencies: 264
-- Name: user_param_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.user_param_id_seq', 512, true);


--
-- TOC entry 4408 (class 0 OID 0)
-- Dependencies: 266
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.users_id_seq', 27, true);


--
-- TOC entry 4409 (class 0 OID 0)
-- Dependencies: 268
-- Name: watch_id_seq; Type: SEQUENCE SET; Schema: public; Owner: dagaz
--

SELECT pg_catalog.setval('public.watch_id_seq', 1, false);


--
-- TOC entry 3915 (class 2606 OID 1810448)
-- Name: db_param PK_00b97969150197eab548d74c749; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.db_param
    ADD CONSTRAINT "PK_00b97969150197eab548d74c749" PRIMARY KEY (id);


--
-- TOC entry 4029 (class 2606 OID 1810450)
-- Name: response_param PK_060398eaf7f7312dda0f5abb596; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.response_param
    ADD CONSTRAINT "PK_060398eaf7f7312dda0f5abb596" PRIMARY KEY (id);


--
-- TOC entry 3989 (class 2606 OID 1810452)
-- Name: quest PK_0d6873502a58302d2ae0b82631c; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest
    ADD CONSTRAINT "PK_0d6873502a58302d2ae0b82631c" PRIMARY KEY (id);


--
-- TOC entry 3953 (class 2606 OID 1810454)
-- Name: job_data PK_132331c9d579dd363e6e33e0bdd; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.job_data
    ADD CONSTRAINT "PK_132331c9d579dd363e6e33e0bdd" PRIMARY KEY (id);


--
-- TOC entry 4017 (class 2606 OID 1810456)
-- Name: request PK_167d324701e6867f189aed52e18; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.request
    ADD CONSTRAINT "PK_167d324701e6867f189aed52e18" PRIMARY KEY (id);


--
-- TOC entry 3978 (class 2606 OID 1810458)
-- Name: node_type PK_21db5612f4dbffd0e468819c4ae; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.node_type
    ADD CONSTRAINT "PK_21db5612f4dbffd0e468819c4ae" PRIMARY KEY (id);


--
-- TOC entry 4049 (class 2606 OID 1810460)
-- Name: user_param PK_28176b67eb400751f274d37ceaa; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.user_param
    ADD CONSTRAINT "PK_28176b67eb400751f274d37ceaa" PRIMARY KEY (id);


--
-- TOC entry 3994 (class 2606 OID 1810462)
-- Name: quest_context PK_292168223e12f455df943997406; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_context
    ADD CONSTRAINT "PK_292168223e12f455df943997406" PRIMARY KEY (id);


--
-- TOC entry 3888 (class 2606 OID 1810464)
-- Name: action PK_2d9db9cf5edfbbae74eb56e3a39; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.action
    ADD CONSTRAINT "PK_2d9db9cf5edfbbae74eb56e3a39" PRIMARY KEY (id);


--
-- TOC entry 4067 (class 2606 OID 1813508)
-- Name: clear_params PK_2e25c5d4cab045f370c01cea934; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.clear_params
    ADD CONSTRAINT "PK_2e25c5d4cab045f370c01cea934" PRIMARY KEY (id);


--
-- TOC entry 3922 (class 2606 OID 1810466)
-- Name: dbproc PK_347a8c4db5bcb356725698bf4fb; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.dbproc
    ADD CONSTRAINT "PK_347a8c4db5bcb356725698bf4fb" PRIMARY KEY (id);


--
-- TOC entry 3941 (class 2606 OID 1810468)
-- Name: game PK_352a30652cd352f552fef73dec5; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.game
    ADD CONSTRAINT "PK_352a30652cd352f552fef73dec5" PRIMARY KEY (id);


--
-- TOC entry 3984 (class 2606 OID 1810470)
-- Name: param_type PK_381c87a7ef163ac5f5d0a0263be; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.param_type
    ADD CONSTRAINT "PK_381c87a7ef163ac5f5d0a0263be" PRIMARY KEY (id);


--
-- TOC entry 4006 (class 2606 OID 1810472)
-- Name: quest_param PK_3ae8947e3e653f4079ee5d4e12d; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_param
    ADD CONSTRAINT "PK_3ae8947e3e653f4079ee5d4e12d" PRIMARY KEY (id);


--
-- TOC entry 3956 (class 2606 OID 1810474)
-- Name: localized_string PK_3d87c2f47c074f8444b233f34c1; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.localized_string
    ADD CONSTRAINT "PK_3d87c2f47c074f8444b233f34c1" PRIMARY KEY (id);


--
-- TOC entry 4013 (class 2606 OID 1810476)
-- Name: quest_subs PK_3e2652420789f1a2523337eed34; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_subs
    ADD CONSTRAINT "PK_3e2652420789f1a2523337eed34" PRIMARY KEY (id);


--
-- TOC entry 4042 (class 2606 OID 1810478)
-- Name: server_option PK_4a63aee543aefce1f69f602f6a9; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.server_option
    ADD CONSTRAINT "PK_4a63aee543aefce1f69f602f6a9" PRIMARY KEY (id);


--
-- TOC entry 4021 (class 2606 OID 1810480)
-- Name: request_param PK_4acba212601abfaf5f48b79ebf3; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.request_param
    ADD CONSTRAINT "PK_4acba212601abfaf5f48b79ebf3" PRIMARY KEY (id);


--
-- TOC entry 3919 (class 2606 OID 1810482)
-- Name: db_result PK_4e8f774e16c0dc26dffffcf9fd7; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.db_result
    ADD CONSTRAINT "PK_4e8f774e16c0dc26dffffcf9fd7" PRIMARY KEY (id);


--
-- TOC entry 3881 (class 2606 OID 1810484)
-- Name: account PK_54115ee388cdb6d86bb4bf5b2ea; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.account
    ADD CONSTRAINT "PK_54115ee388cdb6d86bb4bf5b2ea" PRIMARY KEY (id);


--
-- TOC entry 3892 (class 2606 OID 1810486)
-- Name: action_log PK_63cffa5d8af90621882f0388359; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.action_log
    ADD CONSTRAINT "PK_63cffa5d8af90621882f0388359" PRIMARY KEY (id);


--
-- TOC entry 3902 (class 2606 OID 1810488)
-- Name: command_queue PK_6627a821b98d77204a620dd423c; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.command_queue
    ADD CONSTRAINT "PK_6627a821b98d77204a620dd423c" PRIMARY KEY (id);


--
-- TOC entry 4071 (class 2606 OID 1813578)
-- Name: command_param PK_66e28ba00b30f10113044505957; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.command_param
    ADD CONSTRAINT "PK_66e28ba00b30f10113044505957" PRIMARY KEY (id);


--
-- TOC entry 4003 (class 2606 OID 1810490)
-- Name: quest_info PK_6d4d1d04c9821e0be5f0d51e0c7; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_info
    ADD CONSTRAINT "PK_6d4d1d04c9821e0be5f0d51e0c7" PRIMARY KEY (id);


--
-- TOC entry 3976 (class 2606 OID 1810492)
-- Name: node_info PK_724f5bfaa92ca117c50c533cbbf; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.node_info
    ADD CONSTRAINT "PK_724f5bfaa92ca117c50c533cbbf" PRIMARY KEY (id);


--
-- TOC entry 3934 (class 2606 OID 1810494)
-- Name: edge_info PK_7892d91c776efc18b6de9a9b493; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.edge_info
    ADD CONSTRAINT "PK_7892d91c776efc18b6de9a9b493" PRIMARY KEY (id);


--
-- TOC entry 3938 (class 2606 OID 1810496)
-- Name: edge_param PK_7a601c0b9138f1addb07fef77c8; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.edge_param
    ADD CONSTRAINT "PK_7a601c0b9138f1addb07fef77c8" PRIMARY KEY (id);


--
-- TOC entry 4063 (class 2606 OID 1810498)
-- Name: watch_type PK_81a59d0450feb6e2ce1a6c8417f; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.watch_type
    ADD CONSTRAINT "PK_81a59d0450feb6e2ce1a6c8417f" PRIMARY KEY (id);


--
-- TOC entry 3907 (class 2606 OID 1810500)
-- Name: common_context PK_85ab5ea789d02910bf0fbc9d00c; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.common_context
    ADD CONSTRAINT "PK_85ab5ea789d02910bf0fbc9d00c" PRIMARY KEY (id);


--
-- TOC entry 3999 (class 2606 OID 1810502)
-- Name: quest_grant PK_87498b3b9683b3a671916554a04; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_grant
    ADD CONSTRAINT "PK_87498b3b9683b3a671916554a04" PRIMARY KEY (id);


--
-- TOC entry 3963 (class 2606 OID 1810504)
-- Name: migrations PK_8c82d7f526340ab734260ea46be; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.migrations
    ADD CONSTRAINT "PK_8c82d7f526340ab734260ea46be" PRIMARY KEY (id);


--
-- TOC entry 3968 (class 2606 OID 1810506)
-- Name: node PK_8c8caf5f29d25264abe9eaf94dd; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.node
    ADD CONSTRAINT "PK_8c8caf5f29d25264abe9eaf94dd" PRIMARY KEY (id);


--
-- TOC entry 4031 (class 2606 OID 1810508)
-- Name: script PK_90683f80965555e177a0e7346af; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.script
    ADD CONSTRAINT "PK_90683f80965555e177a0e7346af" PRIMARY KEY (id);


--
-- TOC entry 3949 (class 2606 OID 1810510)
-- Name: job PK_98ab1c14ff8d1cf80d18703b92f; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.job
    ADD CONSTRAINT "PK_98ab1c14ff8d1cf80d18703b92f" PRIMARY KEY (id);


--
-- TOC entry 4010 (class 2606 OID 1810512)
-- Name: quest_stat PK_a3f7e1ef373e887fd9dc4427957; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_stat
    ADD CONSTRAINT "PK_a3f7e1ef373e887fd9dc4427957" PRIMARY KEY (id);


--
-- TOC entry 4053 (class 2606 OID 1810514)
-- Name: users PK_a3ffb1c0c8416b9fc6f907b7433; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT "PK_a3ffb1c0c8416b9fc6f907b7433" PRIMARY KEY (id);


--
-- TOC entry 3970 (class 2606 OID 1810516)
-- Name: node_image PK_b862290c73d4d82eb8bb69cc5db; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.node_image
    ADD CONSTRAINT "PK_b862290c73d4d82eb8bb69cc5db" PRIMARY KEY (id);


--
-- TOC entry 3961 (class 2606 OID 1810518)
-- Name: message PK_ba01f0a3e0123651915008bc578; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.message
    ADD CONSTRAINT "PK_ba01f0a3e0123651915008bc578" PRIMARY KEY (id);


--
-- TOC entry 3927 (class 2606 OID 1810520)
-- Name: edge PK_bf6f43c9af56d05094d8c57b311; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.edge
    ADD CONSTRAINT "PK_bf6f43c9af56d05094d8c57b311" PRIMARY KEY (id);


--
-- TOC entry 3943 (class 2606 OID 1810522)
-- Name: info_type PK_c643c6f06539c2314cddfc9b911; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.info_type
    ADD CONSTRAINT "PK_c643c6f06539c2314cddfc9b911" PRIMARY KEY (id);


--
-- TOC entry 3894 (class 2606 OID 1810524)
-- Name: action_type PK_d1c2e72ba9b5780623b78dde3f5; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.action_type
    ADD CONSTRAINT "PK_d1c2e72ba9b5780623b78dde3f5" PRIMARY KEY (id);


--
-- TOC entry 3931 (class 2606 OID 1810526)
-- Name: edge_cnt PK_d606a87dd9803493af208f3b36b; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.edge_cnt
    ADD CONSTRAINT "PK_d606a87dd9803493af208f3b36b" PRIMARY KEY (id);


--
-- TOC entry 4044 (class 2606 OID 1810528)
-- Name: server_type PK_d9371787ecdfa78b7a68201872b; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.server_type
    ADD CONSTRAINT "PK_d9371787ecdfa78b7a68201872b" PRIMARY KEY (id);


--
-- TOC entry 3898 (class 2606 OID 1810530)
-- Name: client_message PK_e0575b12011a2d8a2e82ccdc899; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.client_message
    ADD CONSTRAINT "PK_e0575b12011a2d8a2e82ccdc899" PRIMARY KEY (id);


--
-- TOC entry 3911 (class 2606 OID 1810532)
-- Name: db_action PK_e932eed00d9b667f7dbb3fca9ae; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.db_action
    ADD CONSTRAINT "PK_e932eed00d9b667f7dbb3fca9ae" PRIMARY KEY (id);


--
-- TOC entry 4035 (class 2606 OID 1810534)
-- Name: script_param PK_f4a15b9ae0f64b7a1b326b1d8f7; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.script_param
    ADD CONSTRAINT "PK_f4a15b9ae0f64b7a1b326b1d8f7" PRIMARY KEY (id);


--
-- TOC entry 4025 (class 2606 OID 1810536)
-- Name: response PK_f64544baf2b4dc48ba623ce768f; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.response
    ADD CONSTRAINT "PK_f64544baf2b4dc48ba623ce768f" PRIMARY KEY (id);


--
-- TOC entry 4038 (class 2606 OID 1810538)
-- Name: server PK_f8b8af38bdc23b447c0a57c7937; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.server
    ADD CONSTRAINT "PK_f8b8af38bdc23b447c0a57c7937" PRIMARY KEY (id);


--
-- TOC entry 3982 (class 2606 OID 1810540)
-- Name: option_type PK_f8f3fdf1eb00de49126c04195e7; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.option_type
    ADD CONSTRAINT "PK_f8f3fdf1eb00de49126c04195e7" PRIMARY KEY (id);


--
-- TOC entry 4061 (class 2606 OID 1810542)
-- Name: watch PK_fcd14254f9a60722c954c0174d0; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.watch
    ADD CONSTRAINT "PK_fcd14254f9a60722c954c0174d0" PRIMARY KEY (id);


--
-- TOC entry 3945 (class 2606 OID 1810544)
-- Name: info_type UQ_1ad1750c41a65762a108bd0d7be; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.info_type
    ADD CONSTRAINT "UQ_1ad1750c41a65762a108bd0d7be" UNIQUE (name);


--
-- TOC entry 3972 (class 2606 OID 1810546)
-- Name: node_image UQ_239f4597c26af0bb00640d40a3b; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.node_image
    ADD CONSTRAINT "UQ_239f4597c26af0bb00640d40a3b" UNIQUE (filename);


--
-- TOC entry 3980 (class 2606 OID 1810548)
-- Name: node_type UQ_53562b28771b4d09996aa27c193; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.node_type
    ADD CONSTRAINT "UQ_53562b28771b4d09996aa27c193" UNIQUE (name);


--
-- TOC entry 3986 (class 2606 OID 1810550)
-- Name: param_type UQ_6722363be3cbc9b8fe27cf53267; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.param_type
    ADD CONSTRAINT "UQ_6722363be3cbc9b8fe27cf53267" UNIQUE (name);


--
-- TOC entry 4055 (class 2606 OID 1810552)
-- Name: users UQ_fe0bb3f6520ee0469504521e710; Type: CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT "UQ_fe0bb3f6520ee0469504521e710" UNIQUE (username);


--
-- TOC entry 4045 (class 1259 OID 1810553)
-- Name: IDX_026fff28b340a045e31d32164c; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_026fff28b340a045e31d32164c" ON public.user_param USING btree (account_id);


--
-- TOC entry 3889 (class 1259 OID 1810554)
-- Name: IDX_0280fa9076adbf5d7cd7fb53c0; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_0280fa9076adbf5d7cd7fb53c0" ON public.action_log USING btree (action_id);


--
-- TOC entry 4000 (class 1259 OID 1810555)
-- Name: IDX_039e11061bd3581cbfdf4cb69d; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_039e11061bd3581cbfdf4cb69d" ON public.quest_info USING btree (type_id);


--
-- TOC entry 3923 (class 1259 OID 1810556)
-- Name: IDX_043246c5fa0a7b1e7be2cb1eac; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_043246c5fa0a7b1e7be2cb1eac" ON public.edge USING btree (to_id);


--
-- TOC entry 3957 (class 1259 OID 1810557)
-- Name: IDX_056d9e9fa79f72683e2f03724f; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_056d9e9fa79f72683e2f03724f" ON public.message USING btree (scheduled);


--
-- TOC entry 4022 (class 1259 OID 1810558)
-- Name: IDX_0799adb0ae11661f7afb4a7549; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_0799adb0ae11661f7afb4a7549" ON public.response USING btree (request_id);


--
-- TOC entry 3939 (class 1259 OID 1810559)
-- Name: IDX_083453ab918bd78b046351dc20; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_083453ab918bd78b046351dc20" ON public.game USING btree (parent_id);


--
-- TOC entry 4056 (class 1259 OID 1810560)
-- Name: IDX_0a5a7fe85fe97e12d240098501; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_0a5a7fe85fe97e12d240098501" ON public.watch USING btree (user_id);


--
-- TOC entry 3928 (class 1259 OID 1810561)
-- Name: IDX_1124ee83db3e09d701e9d44813; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_1124ee83db3e09d701e9d44813" ON public.edge_cnt USING btree (context_id);


--
-- TOC entry 4004 (class 1259 OID 1810562)
-- Name: IDX_130d8bf238d468b206d4c9393c; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_130d8bf238d468b206d4c9393c" ON public.quest_param USING btree (quest_id);


--
-- TOC entry 3908 (class 1259 OID 1810563)
-- Name: IDX_16308019b0f7f08a066a5247f8; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_16308019b0f7f08a066a5247f8" ON public.db_action USING btree (result_id);


--
-- TOC entry 3973 (class 1259 OID 1810564)
-- Name: IDX_1c0cc79637dd3d8f63dd9a53cd; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_1c0cc79637dd3d8f63dd9a53cd" ON public.node_info USING btree (image_id);


--
-- TOC entry 4032 (class 1259 OID 1810565)
-- Name: IDX_1c7a77eb7a3daec5fa0567a445; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_1c7a77eb7a3daec5fa0567a445" ON public.script_param USING btree (script_id);


--
-- TOC entry 4026 (class 1259 OID 1810566)
-- Name: IDX_1eb846d6ec7d144991fbd2b452; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_1eb846d6ec7d144991fbd2b452" ON public.response_param USING btree (paramtype_id);


--
-- TOC entry 3890 (class 1259 OID 1810567)
-- Name: IDX_200fe513550b423fbc980dbda7; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_200fe513550b423fbc980dbda7" ON public.action_log USING btree (account_id);


--
-- TOC entry 3916 (class 1259 OID 1810568)
-- Name: IDX_201dbfda43ef6326ffbb0727fb; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_201dbfda43ef6326ffbb0727fb" ON public.db_result USING btree (paramtype_id);


--
-- TOC entry 3964 (class 1259 OID 1810569)
-- Name: IDX_21db5612f4dbffd0e468819c4a; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_21db5612f4dbffd0e468819c4a" ON public.node USING btree (type_id);


--
-- TOC entry 3909 (class 1259 OID 1810570)
-- Name: IDX_27e363a018598e11b1f15eedb0; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_27e363a018598e11b1f15eedb0" ON public.db_action USING btree (action_id);


--
-- TOC entry 4014 (class 1259 OID 1810571)
-- Name: IDX_2c6d697bf4bc8e3f320e1c9a56; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_2c6d697bf4bc8e3f320e1c9a56" ON public.request USING btree (server_id);


--
-- TOC entry 4057 (class 1259 OID 1810572)
-- Name: IDX_2d66d7b39d8eb33937768f3678; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_2d66d7b39d8eb33937768f3678" ON public.watch USING btree (server_id);


--
-- TOC entry 4011 (class 1259 OID 1810573)
-- Name: IDX_3157cfb81cea1cc5b5e911831f; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_3157cfb81cea1cc5b5e911831f" ON public.quest_subs USING btree (quest_id);


--
-- TOC entry 3965 (class 1259 OID 1810574)
-- Name: IDX_3780604c26ad15796b9f30572c; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_3780604c26ad15796b9f30572c" ON public.node USING btree (quest_id);


--
-- TOC entry 3895 (class 1259 OID 1810575)
-- Name: IDX_3b5b89c3a833b64d2ade8ba141; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_3b5b89c3a833b64d2ade8ba141" ON public.client_message USING btree (message_id);


--
-- TOC entry 4018 (class 1259 OID 1810576)
-- Name: IDX_3bb71732d03e940ad8e31bb7c1; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_3bb71732d03e940ad8e31bb7c1" ON public.request_param USING btree (request_id);


--
-- TOC entry 3995 (class 1259 OID 1810577)
-- Name: IDX_3be3696b42f3c4aee89f62d3bc; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_3be3696b42f3c4aee89f62d3bc" ON public.quest_grant USING btree (grantor_id);


--
-- TOC entry 3903 (class 1259 OID 1810578)
-- Name: IDX_3dd19a7be4ba201d5ff98ee747; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_3dd19a7be4ba201d5ff98ee747" ON public.common_context USING btree (scheduled);


--
-- TOC entry 4019 (class 1259 OID 1810579)
-- Name: IDX_4100ec11af165353f58a9be26f; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_4100ec11af165353f58a9be26f" ON public.request_param USING btree (paramtype_id);


--
-- TOC entry 4023 (class 1259 OID 1810580)
-- Name: IDX_411079d4f5ab0460db9806bf03; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_411079d4f5ab0460db9806bf03" ON public.response USING btree (action_id);


--
-- TOC entry 3950 (class 1259 OID 1810581)
-- Name: IDX_4459ef55e0966d13bc6765cdd3; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_4459ef55e0966d13bc6765cdd3" ON public.job_data USING btree (server_id);


--
-- TOC entry 3920 (class 1259 OID 1810582)
-- Name: IDX_49a07c491eeeeff0a6fb39e4eb; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_49a07c491eeeeff0a6fb39e4eb" ON public.dbproc USING btree (actiontype_id);


--
-- TOC entry 3958 (class 1259 OID 1810583)
-- Name: IDX_54ce30caeb3f33d68398ea1037; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_54ce30caeb3f33d68398ea1037" ON public.message USING btree (user_id);


--
-- TOC entry 3974 (class 1259 OID 1810584)
-- Name: IDX_55aef0d15d6386b16dfedec464; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_55aef0d15d6386b16dfedec464" ON public.node_info USING btree (node_id);


--
-- TOC entry 4058 (class 1259 OID 1810585)
-- Name: IDX_59e70b861cfe8ccf182615a91c; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_59e70b861cfe8ccf182615a91c" ON public.watch USING btree (parent_id);


--
-- TOC entry 4033 (class 1259 OID 1810586)
-- Name: IDX_6516280a953c0a48cbf5d058fd; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_6516280a953c0a48cbf5d058fd" ON public.script_param USING btree (paramtype_id);


--
-- TOC entry 3996 (class 1259 OID 1810587)
-- Name: IDX_652ac39c2620dd3ec54f464ae4; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_652ac39c2620dd3ec54f464ae4" ON public.quest_grant USING btree (quest_id);


--
-- TOC entry 3935 (class 1259 OID 1810588)
-- Name: IDX_7150a8a44ce1bdd2950d03c373; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_7150a8a44ce1bdd2950d03c373" ON public.edge_param USING btree (param_id);


--
-- TOC entry 3924 (class 1259 OID 1810589)
-- Name: IDX_71a6186dbe8a89776b9b820749; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_71a6186dbe8a89776b9b820749" ON public.edge USING btree (quest_id);


--
-- TOC entry 4039 (class 1259 OID 1810590)
-- Name: IDX_71bf40ac3f3fa6cb6b13a22962; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_71bf40ac3f3fa6cb6b13a22962" ON public.server_option USING btree (server_id);


--
-- TOC entry 4050 (class 1259 OID 1810591)
-- Name: IDX_71f902cdeaaffd294c818f6860; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_71f902cdeaaffd294c818f6860" ON public.users USING btree (context_id);


--
-- TOC entry 3882 (class 1259 OID 1810592)
-- Name: IDX_749810f18239007ae8af69d9cc; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_749810f18239007ae8af69d9cc" ON public.action USING btree (script_id);


--
-- TOC entry 4068 (class 1259 OID 1813579)
-- Name: IDX_7828f25615a5ce41531db05030; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_7828f25615a5ce41531db05030" ON public.command_param USING btree (command_id);


--
-- TOC entry 3904 (class 1259 OID 1810593)
-- Name: IDX_7d185c333dd0ff42eef13bb066; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_7d185c333dd0ff42eef13bb066" ON public.common_context USING btree (wait_for);


--
-- TOC entry 4059 (class 1259 OID 1810594)
-- Name: IDX_81a59d0450feb6e2ce1a6c8417; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_81a59d0450feb6e2ce1a6c8417" ON public.watch USING btree (type_id);


--
-- TOC entry 3917 (class 1259 OID 1810595)
-- Name: IDX_8294bc97c0dd97db4f66524113; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_8294bc97c0dd97db4f66524113" ON public.db_result USING btree (proc_id);


--
-- TOC entry 3946 (class 1259 OID 1810596)
-- Name: IDX_87c4a56d5a9c3c366bcaf92dcd; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_87c4a56d5a9c3c366bcaf92dcd" ON public.job USING btree (proc_id);


--
-- TOC entry 3912 (class 1259 OID 1810597)
-- Name: IDX_8bf28f4984026441c92284410a; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_8bf28f4984026441c92284410a" ON public.db_param USING btree (proc_id);


--
-- TOC entry 3987 (class 1259 OID 1810598)
-- Name: IDX_9054662a343fc438df763783cc; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_9054662a343fc438df763783cc" ON public.quest USING btree (account_id);


--
-- TOC entry 3877 (class 1259 OID 1810599)
-- Name: IDX_9235af5a3c3ff3b64dbfc54e8a; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_9235af5a3c3ff3b64dbfc54e8a" ON public.account USING btree (context_id);


--
-- TOC entry 3997 (class 1259 OID 1810600)
-- Name: IDX_a007b700c244b54a9b03ee6286; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_a007b700c244b54a9b03ee6286" ON public.quest_grant USING btree (grant_to);


--
-- TOC entry 3905 (class 1259 OID 1810601)
-- Name: IDX_ab2298f76536b124a37b3fbcca; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_ab2298f76536b124a37b3fbcca" ON public.common_context USING btree (action_id);


--
-- TOC entry 4046 (class 1259 OID 1810602)
-- Name: IDX_b2744c6bb6f12eedc61dab65e2; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_b2744c6bb6f12eedc61dab65e2" ON public.user_param USING btree (user_id);


--
-- TOC entry 3913 (class 1259 OID 1810603)
-- Name: IDX_b81976d15209f94416a21893ca; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_b81976d15209f94416a21893ca" ON public.db_param USING btree (paramtype_id);


--
-- TOC entry 3966 (class 1259 OID 1810604)
-- Name: IDX_b862290c73d4d82eb8bb69cc5d; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_b862290c73d4d82eb8bb69cc5d" ON public.node USING btree (image_id);


--
-- TOC entry 3929 (class 1259 OID 1810605)
-- Name: IDX_ba0efbbfc447b547744fb2d5b9; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_ba0efbbfc447b547744fb2d5b9" ON public.edge_cnt USING btree (edge_id);


--
-- TOC entry 4040 (class 1259 OID 1810606)
-- Name: IDX_bc11440cbddcf89ea8512854a8; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_bc11440cbddcf89ea8512854a8" ON public.server_option USING btree (type_id);


--
-- TOC entry 3947 (class 1259 OID 1810607)
-- Name: IDX_be981b8f8d402409a3434ca5d4; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_be981b8f8d402409a3434ca5d4" ON public.job USING btree (request_id);


--
-- TOC entry 3883 (class 1259 OID 1810608)
-- Name: IDX_c193c40e71f207c07866b5f54a; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_c193c40e71f207c07866b5f54a" ON public.action USING btree (follow_to);


--
-- TOC entry 4069 (class 1259 OID 1813580)
-- Name: IDX_c3365a0f9296dc645542b98714; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_c3365a0f9296dc645542b98714" ON public.command_param USING btree (paramtype_id);


--
-- TOC entry 3925 (class 1259 OID 1810609)
-- Name: IDX_c6bc5f551c85a4abe902748d24; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_c6bc5f551c85a4abe902748d24" ON public.edge USING btree (from_id);


--
-- TOC entry 3936 (class 1259 OID 1810610)
-- Name: IDX_c72d97364af65072c2b2ddfd65; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_c72d97364af65072c2b2ddfd65" ON public.edge_param USING btree (edge_id);


--
-- TOC entry 4007 (class 1259 OID 1810611)
-- Name: IDX_c8b02be5d006ec3220a2280847; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_c8b02be5d006ec3220a2280847" ON public.quest_stat USING btree (account_id);


--
-- TOC entry 3896 (class 1259 OID 1810612)
-- Name: IDX_ca9a35f81f3deaa640871b714d; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_ca9a35f81f3deaa640871b714d" ON public.client_message USING btree (parent_id);


--
-- TOC entry 3954 (class 1259 OID 1810613)
-- Name: IDX_cf9733a3ff386af2c534a0e135; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_cf9733a3ff386af2c534a0e135" ON public.localized_string USING btree (action_id);


--
-- TOC entry 4027 (class 1259 OID 1810614)
-- Name: IDX_cfd31f3fe0c81f4c60103496b6; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_cfd31f3fe0c81f4c60103496b6" ON public.response_param USING btree (response_id);


--
-- TOC entry 3878 (class 1259 OID 1810615)
-- Name: IDX_d09d551463099494ab8632f3e9; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_d09d551463099494ab8632f3e9" ON public.account USING btree (server_id);


--
-- TOC entry 3884 (class 1259 OID 1810616)
-- Name: IDX_d1c2e72ba9b5780623b78dde3f; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_d1c2e72ba9b5780623b78dde3f" ON public.action USING btree (type_id);


--
-- TOC entry 3899 (class 1259 OID 1810617)
-- Name: IDX_d1c4940217c8eb1e191ebb4a86; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_d1c4940217c8eb1e191ebb4a86" ON public.command_queue USING btree (action_id);


--
-- TOC entry 4015 (class 1259 OID 1810618)
-- Name: IDX_d1e8e3adc4d12d221c3b034714; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_d1e8e3adc4d12d221c3b034714" ON public.request USING btree (actiontype_id);


--
-- TOC entry 4047 (class 1259 OID 1810619)
-- Name: IDX_d1fc506598dcf55ce41c27ed82; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_d1fc506598dcf55ce41c27ed82" ON public.user_param USING btree (type_id);


--
-- TOC entry 3959 (class 1259 OID 1810620)
-- Name: IDX_d22ce64c762531de8fb38c4913; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_d22ce64c762531de8fb38c4913" ON public.message USING btree (send_to);


--
-- TOC entry 4064 (class 1259 OID 1813509)
-- Name: IDX_d54add567800c92e139ecfa93b; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_d54add567800c92e139ecfa93b" ON public.clear_params USING btree (paramtype_id);


--
-- TOC entry 4001 (class 1259 OID 1810621)
-- Name: IDX_d58543ce2773e4eef4f3d5be23; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_d58543ce2773e4eef4f3d5be23" ON public.quest_info USING btree (quest_id);


--
-- TOC entry 3990 (class 1259 OID 1810622)
-- Name: IDX_d90e8b70695dd8e30649170efe; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_d90e8b70695dd8e30649170efe" ON public.quest_context USING btree (image_id);


--
-- TOC entry 4036 (class 1259 OID 1810623)
-- Name: IDX_d9371787ecdfa78b7a68201872; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_d9371787ecdfa78b7a68201872" ON public.server USING btree (type_id);


--
-- TOC entry 3900 (class 1259 OID 1810624)
-- Name: IDX_dcf9ef2e51e2128062355742d3; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_dcf9ef2e51e2128062355742d3" ON public.command_queue USING btree (context_id);


--
-- TOC entry 3885 (class 1259 OID 1810625)
-- Name: IDX_dd9f38f7d283e189cb6a6c9b84; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_dd9f38f7d283e189cb6a6c9b84" ON public.action USING btree (parent_id);


--
-- TOC entry 3886 (class 1259 OID 1810626)
-- Name: IDX_de889e5cf4ca9ac70019b43cc8; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_de889e5cf4ca9ac70019b43cc8" ON public.action USING btree (paramtype_id);


--
-- TOC entry 3951 (class 1259 OID 1810627)
-- Name: IDX_df1c3cb010cfb93c5ced140c67; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_df1c3cb010cfb93c5ced140c67" ON public.job_data USING btree (job_id);


--
-- TOC entry 4065 (class 1259 OID 1813525)
-- Name: IDX_e49bf6977925577f8f4ae4d709; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_e49bf6977925577f8f4ae4d709" ON public.clear_params USING btree (action_id);


--
-- TOC entry 3932 (class 1259 OID 1810628)
-- Name: IDX_efac6fdb01af430ebe7b646c19; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_efac6fdb01af430ebe7b646c19" ON public.edge_info USING btree (edge_id);


--
-- TOC entry 3879 (class 1259 OID 1810629)
-- Name: IDX_efef1e5fdbe318a379c06678c5; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_efef1e5fdbe318a379c06678c5" ON public.account USING btree (user_id);


--
-- TOC entry 3991 (class 1259 OID 1810630)
-- Name: IDX_f52beec31634ed2e05c685b8ef; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_f52beec31634ed2e05c685b8ef" ON public.quest_context USING btree (node_id);


--
-- TOC entry 4008 (class 1259 OID 1810631)
-- Name: IDX_f66b012cad57c4dd674616029d; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_f66b012cad57c4dd674616029d" ON public.quest_stat USING btree (quest_id);


--
-- TOC entry 3992 (class 1259 OID 1810632)
-- Name: IDX_f8d8149f8fc59ee4d08c441038; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_f8d8149f8fc59ee4d08c441038" ON public.quest_context USING btree (action_id);


--
-- TOC entry 4051 (class 1259 OID 1810633)
-- Name: IDX_fe0bb3f6520ee0469504521e71; Type: INDEX; Schema: public; Owner: dagaz
--

CREATE INDEX "IDX_fe0bb3f6520ee0469504521e71" ON public.users USING btree (username);


--
-- TOC entry 4141 (class 2606 OID 1810634)
-- Name: user_param FK_026fff28b340a045e31d32164c9; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.user_param
    ADD CONSTRAINT "FK_026fff28b340a045e31d32164c9" FOREIGN KEY (account_id) REFERENCES public.account(id);


--
-- TOC entry 4080 (class 2606 OID 1810639)
-- Name: action_log FK_0280fa9076adbf5d7cd7fb53c09; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.action_log
    ADD CONSTRAINT "FK_0280fa9076adbf5d7cd7fb53c09" FOREIGN KEY (action_id) REFERENCES public.action(id);


--
-- TOC entry 4122 (class 2606 OID 1810644)
-- Name: quest_info FK_039e11061bd3581cbfdf4cb69d8; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_info
    ADD CONSTRAINT "FK_039e11061bd3581cbfdf4cb69d8" FOREIGN KEY (type_id) REFERENCES public.info_type(id);


--
-- TOC entry 4094 (class 2606 OID 1810649)
-- Name: edge FK_043246c5fa0a7b1e7be2cb1eac9; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.edge
    ADD CONSTRAINT "FK_043246c5fa0a7b1e7be2cb1eac9" FOREIGN KEY (to_id) REFERENCES public.node(id);


--
-- TOC entry 4132 (class 2606 OID 1810654)
-- Name: response FK_0799adb0ae11661f7afb4a75496; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.response
    ADD CONSTRAINT "FK_0799adb0ae11661f7afb4a75496" FOREIGN KEY (request_id) REFERENCES public.request(id);


--
-- TOC entry 4102 (class 2606 OID 1810659)
-- Name: game FK_083453ab918bd78b046351dc207; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.game
    ADD CONSTRAINT "FK_083453ab918bd78b046351dc207" FOREIGN KEY (parent_id) REFERENCES public.game(id);


--
-- TOC entry 4145 (class 2606 OID 1810664)
-- Name: watch FK_0a5a7fe85fe97e12d240098501c; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.watch
    ADD CONSTRAINT "FK_0a5a7fe85fe97e12d240098501c" FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- TOC entry 4097 (class 2606 OID 1810669)
-- Name: edge_cnt FK_1124ee83db3e09d701e9d44813a; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.edge_cnt
    ADD CONSTRAINT "FK_1124ee83db3e09d701e9d44813a" FOREIGN KEY (context_id) REFERENCES public.quest_context(id);


--
-- TOC entry 4124 (class 2606 OID 1810674)
-- Name: quest_param FK_130d8bf238d468b206d4c9393cd; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_param
    ADD CONSTRAINT "FK_130d8bf238d468b206d4c9393cd" FOREIGN KEY (quest_id) REFERENCES public.quest(id);


--
-- TOC entry 4087 (class 2606 OID 1810679)
-- Name: db_action FK_16308019b0f7f08a066a5247f8b; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.db_action
    ADD CONSTRAINT "FK_16308019b0f7f08a066a5247f8b" FOREIGN KEY (result_id) REFERENCES public.db_result(id);


--
-- TOC entry 4113 (class 2606 OID 1810684)
-- Name: node_info FK_1c0cc79637dd3d8f63dd9a53cda; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.node_info
    ADD CONSTRAINT "FK_1c0cc79637dd3d8f63dd9a53cda" FOREIGN KEY (image_id) REFERENCES public.node_image(id);


--
-- TOC entry 4136 (class 2606 OID 1810689)
-- Name: script_param FK_1c7a77eb7a3daec5fa0567a4456; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.script_param
    ADD CONSTRAINT "FK_1c7a77eb7a3daec5fa0567a4456" FOREIGN KEY (script_id) REFERENCES public.script(id);


--
-- TOC entry 4134 (class 2606 OID 1810694)
-- Name: response_param FK_1eb846d6ec7d144991fbd2b4528; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.response_param
    ADD CONSTRAINT "FK_1eb846d6ec7d144991fbd2b4528" FOREIGN KEY (paramtype_id) REFERENCES public.param_type(id);


--
-- TOC entry 4081 (class 2606 OID 1810699)
-- Name: action_log FK_200fe513550b423fbc980dbda7c; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.action_log
    ADD CONSTRAINT "FK_200fe513550b423fbc980dbda7c" FOREIGN KEY (account_id) REFERENCES public.account(id);


--
-- TOC entry 4091 (class 2606 OID 1810704)
-- Name: db_result FK_201dbfda43ef6326ffbb0727fb8; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.db_result
    ADD CONSTRAINT "FK_201dbfda43ef6326ffbb0727fb8" FOREIGN KEY (paramtype_id) REFERENCES public.param_type(id);


--
-- TOC entry 4110 (class 2606 OID 1810709)
-- Name: node FK_21db5612f4dbffd0e468819c4ae; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.node
    ADD CONSTRAINT "FK_21db5612f4dbffd0e468819c4ae" FOREIGN KEY (type_id) REFERENCES public.node_type(id);


--
-- TOC entry 4088 (class 2606 OID 1810714)
-- Name: db_action FK_27e363a018598e11b1f15eedb09; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.db_action
    ADD CONSTRAINT "FK_27e363a018598e11b1f15eedb09" FOREIGN KEY (action_id) REFERENCES public.action(id);


--
-- TOC entry 4128 (class 2606 OID 1810719)
-- Name: request FK_2c6d697bf4bc8e3f320e1c9a560; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.request
    ADD CONSTRAINT "FK_2c6d697bf4bc8e3f320e1c9a560" FOREIGN KEY (server_id) REFERENCES public.server(id);


--
-- TOC entry 4146 (class 2606 OID 1810724)
-- Name: watch FK_2d66d7b39d8eb33937768f3678b; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.watch
    ADD CONSTRAINT "FK_2d66d7b39d8eb33937768f3678b" FOREIGN KEY (server_id) REFERENCES public.server(id);


--
-- TOC entry 4127 (class 2606 OID 1810729)
-- Name: quest_subs FK_3157cfb81cea1cc5b5e911831fa; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_subs
    ADD CONSTRAINT "FK_3157cfb81cea1cc5b5e911831fa" FOREIGN KEY (quest_id) REFERENCES public.quest(id);


--
-- TOC entry 4111 (class 2606 OID 1810734)
-- Name: node FK_3780604c26ad15796b9f30572c0; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.node
    ADD CONSTRAINT "FK_3780604c26ad15796b9f30572c0" FOREIGN KEY (quest_id) REFERENCES public.quest(id);


--
-- TOC entry 4130 (class 2606 OID 1810739)
-- Name: request_param FK_3bb71732d03e940ad8e31bb7c13; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.request_param
    ADD CONSTRAINT "FK_3bb71732d03e940ad8e31bb7c13" FOREIGN KEY (request_id) REFERENCES public.request(id);


--
-- TOC entry 4119 (class 2606 OID 1810744)
-- Name: quest_grant FK_3be3696b42f3c4aee89f62d3bcf; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_grant
    ADD CONSTRAINT "FK_3be3696b42f3c4aee89f62d3bcf" FOREIGN KEY (grantor_id) REFERENCES public.action(id);


--
-- TOC entry 4131 (class 2606 OID 1810749)
-- Name: request_param FK_4100ec11af165353f58a9be26fa; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.request_param
    ADD CONSTRAINT "FK_4100ec11af165353f58a9be26fa" FOREIGN KEY (paramtype_id) REFERENCES public.param_type(id);


--
-- TOC entry 4133 (class 2606 OID 1810754)
-- Name: response FK_411079d4f5ab0460db9806bf03c; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.response
    ADD CONSTRAINT "FK_411079d4f5ab0460db9806bf03c" FOREIGN KEY (action_id) REFERENCES public.action(id);


--
-- TOC entry 4105 (class 2606 OID 1810759)
-- Name: job_data FK_4459ef55e0966d13bc6765cdd3d; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.job_data
    ADD CONSTRAINT "FK_4459ef55e0966d13bc6765cdd3d" FOREIGN KEY (server_id) REFERENCES public.server(id);


--
-- TOC entry 4093 (class 2606 OID 1810764)
-- Name: dbproc FK_49a07c491eeeeff0a6fb39e4eb6; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.dbproc
    ADD CONSTRAINT "FK_49a07c491eeeeff0a6fb39e4eb6" FOREIGN KEY (actiontype_id) REFERENCES public.action_type(id);


--
-- TOC entry 4108 (class 2606 OID 1810769)
-- Name: message FK_54ce30caeb3f33d68398ea10376; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.message
    ADD CONSTRAINT "FK_54ce30caeb3f33d68398ea10376" FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- TOC entry 4114 (class 2606 OID 1810774)
-- Name: node_info FK_55aef0d15d6386b16dfedec4648; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.node_info
    ADD CONSTRAINT "FK_55aef0d15d6386b16dfedec4648" FOREIGN KEY (node_id) REFERENCES public.node(id);


--
-- TOC entry 4147 (class 2606 OID 1810779)
-- Name: watch FK_59e70b861cfe8ccf182615a91cb; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.watch
    ADD CONSTRAINT "FK_59e70b861cfe8ccf182615a91cb" FOREIGN KEY (parent_id) REFERENCES public.watch(id);


--
-- TOC entry 4137 (class 2606 OID 1810784)
-- Name: script_param FK_6516280a953c0a48cbf5d058fd2; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.script_param
    ADD CONSTRAINT "FK_6516280a953c0a48cbf5d058fd2" FOREIGN KEY (paramtype_id) REFERENCES public.param_type(id);


--
-- TOC entry 4120 (class 2606 OID 1810789)
-- Name: quest_grant FK_652ac39c2620dd3ec54f464ae4a; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_grant
    ADD CONSTRAINT "FK_652ac39c2620dd3ec54f464ae4a" FOREIGN KEY (quest_id) REFERENCES public.quest(id);


--
-- TOC entry 4100 (class 2606 OID 1810794)
-- Name: edge_param FK_7150a8a44ce1bdd2950d03c373a; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.edge_param
    ADD CONSTRAINT "FK_7150a8a44ce1bdd2950d03c373a" FOREIGN KEY (param_id) REFERENCES public.quest_param(id);


--
-- TOC entry 4095 (class 2606 OID 1810799)
-- Name: edge FK_71a6186dbe8a89776b9b820749e; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.edge
    ADD CONSTRAINT "FK_71a6186dbe8a89776b9b820749e" FOREIGN KEY (quest_id) REFERENCES public.quest(id);


--
-- TOC entry 4139 (class 2606 OID 1810804)
-- Name: server_option FK_71bf40ac3f3fa6cb6b13a229621; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.server_option
    ADD CONSTRAINT "FK_71bf40ac3f3fa6cb6b13a229621" FOREIGN KEY (server_id) REFERENCES public.server(id);


--
-- TOC entry 4144 (class 2606 OID 1810809)
-- Name: users FK_71f902cdeaaffd294c818f68601; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT "FK_71f902cdeaaffd294c818f68601" FOREIGN KEY (context_id) REFERENCES public.common_context(id);


--
-- TOC entry 4075 (class 2606 OID 1810814)
-- Name: action FK_749810f18239007ae8af69d9cc2; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.action
    ADD CONSTRAINT "FK_749810f18239007ae8af69d9cc2" FOREIGN KEY (script_id) REFERENCES public.script(id);


--
-- TOC entry 4151 (class 2606 OID 1813581)
-- Name: command_param FK_7828f25615a5ce41531db050305; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.command_param
    ADD CONSTRAINT "FK_7828f25615a5ce41531db050305" FOREIGN KEY (command_id) REFERENCES public.command_queue(id);


--
-- TOC entry 4085 (class 2606 OID 1810819)
-- Name: common_context FK_7d185c333dd0ff42eef13bb066b; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.common_context
    ADD CONSTRAINT "FK_7d185c333dd0ff42eef13bb066b" FOREIGN KEY (wait_for) REFERENCES public.param_type(id);


--
-- TOC entry 4148 (class 2606 OID 1810824)
-- Name: watch FK_81a59d0450feb6e2ce1a6c8417f; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.watch
    ADD CONSTRAINT "FK_81a59d0450feb6e2ce1a6c8417f" FOREIGN KEY (type_id) REFERENCES public.watch_type(id);


--
-- TOC entry 4092 (class 2606 OID 1810829)
-- Name: db_result FK_8294bc97c0dd97db4f665241132; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.db_result
    ADD CONSTRAINT "FK_8294bc97c0dd97db4f665241132" FOREIGN KEY (proc_id) REFERENCES public.dbproc(id);


--
-- TOC entry 4103 (class 2606 OID 1810834)
-- Name: job FK_87c4a56d5a9c3c366bcaf92dcdd; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.job
    ADD CONSTRAINT "FK_87c4a56d5a9c3c366bcaf92dcdd" FOREIGN KEY (proc_id) REFERENCES public.dbproc(id);


--
-- TOC entry 4089 (class 2606 OID 1810839)
-- Name: db_param FK_8bf28f4984026441c92284410ae; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.db_param
    ADD CONSTRAINT "FK_8bf28f4984026441c92284410ae" FOREIGN KEY (proc_id) REFERENCES public.dbproc(id);


--
-- TOC entry 4115 (class 2606 OID 1810844)
-- Name: quest FK_9054662a343fc438df763783cc9; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest
    ADD CONSTRAINT "FK_9054662a343fc438df763783cc9" FOREIGN KEY (account_id) REFERENCES public.account(id);


--
-- TOC entry 4072 (class 2606 OID 1810849)
-- Name: account FK_9235af5a3c3ff3b64dbfc54e8a3; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.account
    ADD CONSTRAINT "FK_9235af5a3c3ff3b64dbfc54e8a3" FOREIGN KEY (context_id) REFERENCES public.common_context(id);


--
-- TOC entry 4121 (class 2606 OID 1810854)
-- Name: quest_grant FK_a007b700c244b54a9b03ee62864; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_grant
    ADD CONSTRAINT "FK_a007b700c244b54a9b03ee62864" FOREIGN KEY (grant_to) REFERENCES public.action(id);


--
-- TOC entry 4086 (class 2606 OID 1810859)
-- Name: common_context FK_ab2298f76536b124a37b3fbcca5; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.common_context
    ADD CONSTRAINT "FK_ab2298f76536b124a37b3fbcca5" FOREIGN KEY (action_id) REFERENCES public.action(id);


--
-- TOC entry 4142 (class 2606 OID 1810864)
-- Name: user_param FK_b2744c6bb6f12eedc61dab65e25; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.user_param
    ADD CONSTRAINT "FK_b2744c6bb6f12eedc61dab65e25" FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- TOC entry 4090 (class 2606 OID 1810869)
-- Name: db_param FK_b81976d15209f94416a21893cac; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.db_param
    ADD CONSTRAINT "FK_b81976d15209f94416a21893cac" FOREIGN KEY (paramtype_id) REFERENCES public.param_type(id);


--
-- TOC entry 4112 (class 2606 OID 1810874)
-- Name: node FK_b862290c73d4d82eb8bb69cc5db; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.node
    ADD CONSTRAINT "FK_b862290c73d4d82eb8bb69cc5db" FOREIGN KEY (image_id) REFERENCES public.node_image(id);


--
-- TOC entry 4098 (class 2606 OID 1810879)
-- Name: edge_cnt FK_ba0efbbfc447b547744fb2d5b9b; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.edge_cnt
    ADD CONSTRAINT "FK_ba0efbbfc447b547744fb2d5b9b" FOREIGN KEY (edge_id) REFERENCES public.edge(id);


--
-- TOC entry 4140 (class 2606 OID 1810884)
-- Name: server_option FK_bc11440cbddcf89ea8512854a8a; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.server_option
    ADD CONSTRAINT "FK_bc11440cbddcf89ea8512854a8a" FOREIGN KEY (type_id) REFERENCES public.option_type(id);


--
-- TOC entry 4104 (class 2606 OID 1810889)
-- Name: job FK_be981b8f8d402409a3434ca5d4b; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.job
    ADD CONSTRAINT "FK_be981b8f8d402409a3434ca5d4b" FOREIGN KEY (request_id) REFERENCES public.request(id);


--
-- TOC entry 4076 (class 2606 OID 1810894)
-- Name: action FK_c193c40e71f207c07866b5f54a0; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.action
    ADD CONSTRAINT "FK_c193c40e71f207c07866b5f54a0" FOREIGN KEY (follow_to) REFERENCES public.action(id);


--
-- TOC entry 4152 (class 2606 OID 1813586)
-- Name: command_param FK_c3365a0f9296dc645542b987143; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.command_param
    ADD CONSTRAINT "FK_c3365a0f9296dc645542b987143" FOREIGN KEY (paramtype_id) REFERENCES public.param_type(id);


--
-- TOC entry 4096 (class 2606 OID 1810899)
-- Name: edge FK_c6bc5f551c85a4abe902748d24c; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.edge
    ADD CONSTRAINT "FK_c6bc5f551c85a4abe902748d24c" FOREIGN KEY (from_id) REFERENCES public.node(id);


--
-- TOC entry 4101 (class 2606 OID 1810904)
-- Name: edge_param FK_c72d97364af65072c2b2ddfd651; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.edge_param
    ADD CONSTRAINT "FK_c72d97364af65072c2b2ddfd651" FOREIGN KEY (edge_id) REFERENCES public.edge(id);


--
-- TOC entry 4125 (class 2606 OID 1810909)
-- Name: quest_stat FK_c8b02be5d006ec3220a2280847d; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_stat
    ADD CONSTRAINT "FK_c8b02be5d006ec3220a2280847d" FOREIGN KEY (account_id) REFERENCES public.account(id);


--
-- TOC entry 4082 (class 2606 OID 1810914)
-- Name: client_message FK_ca9a35f81f3deaa640871b714d7; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.client_message
    ADD CONSTRAINT "FK_ca9a35f81f3deaa640871b714d7" FOREIGN KEY (parent_id) REFERENCES public.message(id);


--
-- TOC entry 4107 (class 2606 OID 1810919)
-- Name: localized_string FK_cf9733a3ff386af2c534a0e1359; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.localized_string
    ADD CONSTRAINT "FK_cf9733a3ff386af2c534a0e1359" FOREIGN KEY (action_id) REFERENCES public.action(id);


--
-- TOC entry 4135 (class 2606 OID 1810924)
-- Name: response_param FK_cfd31f3fe0c81f4c60103496b62; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.response_param
    ADD CONSTRAINT "FK_cfd31f3fe0c81f4c60103496b62" FOREIGN KEY (response_id) REFERENCES public.response(id);


--
-- TOC entry 4073 (class 2606 OID 1810929)
-- Name: account FK_d09d551463099494ab8632f3e98; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.account
    ADD CONSTRAINT "FK_d09d551463099494ab8632f3e98" FOREIGN KEY (server_id) REFERENCES public.server(id);


--
-- TOC entry 4077 (class 2606 OID 1810934)
-- Name: action FK_d1c2e72ba9b5780623b78dde3f5; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.action
    ADD CONSTRAINT "FK_d1c2e72ba9b5780623b78dde3f5" FOREIGN KEY (type_id) REFERENCES public.action_type(id);


--
-- TOC entry 4083 (class 2606 OID 1810939)
-- Name: command_queue FK_d1c4940217c8eb1e191ebb4a869; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.command_queue
    ADD CONSTRAINT "FK_d1c4940217c8eb1e191ebb4a869" FOREIGN KEY (action_id) REFERENCES public.action(id);


--
-- TOC entry 4129 (class 2606 OID 1810944)
-- Name: request FK_d1e8e3adc4d12d221c3b0347147; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.request
    ADD CONSTRAINT "FK_d1e8e3adc4d12d221c3b0347147" FOREIGN KEY (actiontype_id) REFERENCES public.action_type(id);


--
-- TOC entry 4143 (class 2606 OID 1810949)
-- Name: user_param FK_d1fc506598dcf55ce41c27ed827; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.user_param
    ADD CONSTRAINT "FK_d1fc506598dcf55ce41c27ed827" FOREIGN KEY (type_id) REFERENCES public.param_type(id);


--
-- TOC entry 4109 (class 2606 OID 1810954)
-- Name: message FK_d22ce64c762531de8fb38c49135; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.message
    ADD CONSTRAINT "FK_d22ce64c762531de8fb38c49135" FOREIGN KEY (send_to) REFERENCES public.users(id);


--
-- TOC entry 4149 (class 2606 OID 1813511)
-- Name: clear_params FK_d54add567800c92e139ecfa93bc; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.clear_params
    ADD CONSTRAINT "FK_d54add567800c92e139ecfa93bc" FOREIGN KEY (paramtype_id) REFERENCES public.param_type(id);


--
-- TOC entry 4123 (class 2606 OID 1810959)
-- Name: quest_info FK_d58543ce2773e4eef4f3d5be230; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_info
    ADD CONSTRAINT "FK_d58543ce2773e4eef4f3d5be230" FOREIGN KEY (quest_id) REFERENCES public.quest(id);


--
-- TOC entry 4116 (class 2606 OID 1810964)
-- Name: quest_context FK_d90e8b70695dd8e30649170efe0; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_context
    ADD CONSTRAINT "FK_d90e8b70695dd8e30649170efe0" FOREIGN KEY (image_id) REFERENCES public.node_image(id);


--
-- TOC entry 4138 (class 2606 OID 1810969)
-- Name: server FK_d9371787ecdfa78b7a68201872b; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.server
    ADD CONSTRAINT "FK_d9371787ecdfa78b7a68201872b" FOREIGN KEY (type_id) REFERENCES public.server_type(id);


--
-- TOC entry 4084 (class 2606 OID 1810974)
-- Name: command_queue FK_dcf9ef2e51e2128062355742d33; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.command_queue
    ADD CONSTRAINT "FK_dcf9ef2e51e2128062355742d33" FOREIGN KEY (context_id) REFERENCES public.common_context(id);


--
-- TOC entry 4078 (class 2606 OID 1810979)
-- Name: action FK_dd9f38f7d283e189cb6a6c9b84f; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.action
    ADD CONSTRAINT "FK_dd9f38f7d283e189cb6a6c9b84f" FOREIGN KEY (parent_id) REFERENCES public.action(id);


--
-- TOC entry 4079 (class 2606 OID 1810984)
-- Name: action FK_de889e5cf4ca9ac70019b43cc85; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.action
    ADD CONSTRAINT "FK_de889e5cf4ca9ac70019b43cc85" FOREIGN KEY (paramtype_id) REFERENCES public.param_type(id);


--
-- TOC entry 4106 (class 2606 OID 1810989)
-- Name: job_data FK_df1c3cb010cfb93c5ced140c67d; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.job_data
    ADD CONSTRAINT "FK_df1c3cb010cfb93c5ced140c67d" FOREIGN KEY (job_id) REFERENCES public.job(id);


--
-- TOC entry 4150 (class 2606 OID 1813526)
-- Name: clear_params FK_e49bf6977925577f8f4ae4d7093; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.clear_params
    ADD CONSTRAINT "FK_e49bf6977925577f8f4ae4d7093" FOREIGN KEY (action_id) REFERENCES public.action(id);


--
-- TOC entry 4099 (class 2606 OID 1810994)
-- Name: edge_info FK_efac6fdb01af430ebe7b646c192; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.edge_info
    ADD CONSTRAINT "FK_efac6fdb01af430ebe7b646c192" FOREIGN KEY (edge_id) REFERENCES public.edge(id);


--
-- TOC entry 4074 (class 2606 OID 1810999)
-- Name: account FK_efef1e5fdbe318a379c06678c51; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.account
    ADD CONSTRAINT "FK_efef1e5fdbe318a379c06678c51" FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- TOC entry 4117 (class 2606 OID 1811004)
-- Name: quest_context FK_f52beec31634ed2e05c685b8ef5; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_context
    ADD CONSTRAINT "FK_f52beec31634ed2e05c685b8ef5" FOREIGN KEY (node_id) REFERENCES public.node(id);


--
-- TOC entry 4126 (class 2606 OID 1811009)
-- Name: quest_stat FK_f66b012cad57c4dd674616029dc; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_stat
    ADD CONSTRAINT "FK_f66b012cad57c4dd674616029dc" FOREIGN KEY (quest_id) REFERENCES public.quest(id);


--
-- TOC entry 4118 (class 2606 OID 1811014)
-- Name: quest_context FK_f8d8149f8fc59ee4d08c4410381; Type: FK CONSTRAINT; Schema: public; Owner: dagaz
--

ALTER TABLE ONLY public.quest_context
    ADD CONSTRAINT "FK_f8d8149f8fc59ee4d08c4410381" FOREIGN KEY (action_id) REFERENCES public.action(id);


-- Completed on 2024-01-02 13:54:42

--
-- PostgreSQL database dump complete
--


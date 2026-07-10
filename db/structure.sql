\restrict i2TCI7f7N0AashqeSviLNsiciVEh4MWQYi88yY8ft1vKxQpSWA2MfFDZ2FAMWzn

-- Dumped from database version 17.9 (Homebrew)
-- Dumped by pg_dump version 17.9 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;


--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';


--
-- Name: enforce_access_audit_log_tenant_governance(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_access_audit_log_tenant_governance() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  owner_is_system_admin boolean;
  owner_tenant_id bigint;
BEGIN
  IF NEW.admin_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT super_admin, tenant_id
    INTO owner_is_system_admin, owner_tenant_id
  FROM admin_users
  WHERE id = NEW.admin_user_id;

  IF owner_is_system_admin IS DISTINCT FROM TRUE AND NEW.tenant_id IS NULL THEN
    RAISE EXCEPTION 'access audit log tenant is required for account users'
      USING ERRCODE = '23514';
  END IF;

  IF owner_is_system_admin = TRUE AND NEW.tenant_id IS NOT NULL THEN
    RAISE EXCEPTION 'platform access audit log must not belong to a tenant'
      USING ERRCODE = '23514';
  END IF;

  IF owner_is_system_admin IS DISTINCT FROM TRUE AND owner_tenant_id IS DISTINCT FROM NEW.tenant_id THEN
    RAISE EXCEPTION 'access audit log tenant must match admin user tenant'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: enforce_admin_user_profile_governance(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_admin_user_profile_governance() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  user_profile_axis text;
  user_profile_position integer;
  horizontal_axis text;
  horizontal_root_vertical_id bigint;
  manager_profile_position integer;
  cycle_found boolean;
BEGIN
  IF NEW.profile_id IS NOT NULL THEN
    SELECT axis, position
      INTO user_profile_axis, user_profile_position
    FROM profiles
    WHERE id = NEW.profile_id
      AND tenant_id = NEW.tenant_id;

    IF user_profile_axis IS DISTINCT FROM 'vertical' THEN
      RAISE EXCEPTION 'admin user profile must be a vertical profile from the same tenant'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF NEW.horizontal_profile_id IS NOT NULL THEN
    IF NEW.profile_id IS NULL THEN
      RAISE EXCEPTION 'admin user horizontal profile requires a vertical profile'
        USING ERRCODE = '23514';
    END IF;

    SELECT axis
      INTO horizontal_axis
    FROM profiles
    WHERE id = NEW.horizontal_profile_id
      AND tenant_id = NEW.tenant_id;

    IF horizontal_axis IS DISTINCT FROM 'horizontal' THEN
      RAISE EXCEPTION 'admin user horizontal profile must be a horizontal profile from the same tenant'
        USING ERRCODE = '23514';
    END IF;

    -- Sobe a cadeia de âncoras (função → função → ... → vertical) e
    -- compara a RAIZ vertical com o perfil do usuário.
    WITH RECURSIVE anchor_chain AS (
      SELECT p.id, p.axis, p.vertical_profile_id, 0 AS depth
      FROM profiles p
      WHERE p.id = NEW.horizontal_profile_id
        AND p.tenant_id = NEW.tenant_id
      UNION ALL
      SELECT parent.id, parent.axis, parent.vertical_profile_id, chain.depth + 1
      FROM profiles parent
      JOIN anchor_chain chain ON parent.id = chain.vertical_profile_id
      WHERE chain.axis = 'horizontal'
        AND chain.depth < 6
        AND parent.tenant_id = NEW.tenant_id
    )
    SELECT id
      INTO horizontal_root_vertical_id
    FROM anchor_chain
    WHERE axis = 'vertical'
    LIMIT 1;

    IF horizontal_root_vertical_id IS DISTINCT FROM NEW.profile_id THEN
      RAISE EXCEPTION 'admin user horizontal profile must be attached to the user vertical profile'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF NEW.manager_id IS NOT NULL THEN
    IF NEW.profile_id IS NULL THEN
      RAISE EXCEPTION 'admin user with manager requires a vertical profile'
        USING ERRCODE = '23514';
    END IF;

    SELECT manager_profile.position
      INTO manager_profile_position
    FROM admin_users manager
    JOIN profiles manager_profile
      ON manager_profile.id = manager.profile_id
     AND manager_profile.tenant_id = manager.tenant_id
    WHERE manager.id = NEW.manager_id
      AND manager.tenant_id = NEW.tenant_id
      AND manager_profile.axis = 'vertical';

    IF manager_profile_position IS NULL OR manager_profile_position >= user_profile_position THEN
      RAISE EXCEPTION 'admin user manager must be above the user vertical profile'
        USING ERRCODE = '23514';
    END IF;

    IF NEW.id IS NOT NULL THEN
      WITH RECURSIVE subtree AS (
        SELECT id
        FROM admin_users
        WHERE manager_id = NEW.id
          AND tenant_id = NEW.tenant_id
        UNION ALL
        SELECT child.id
        FROM admin_users child
        JOIN subtree parent ON child.manager_id = parent.id
        WHERE child.tenant_id = NEW.tenant_id
      )
      SELECT EXISTS(SELECT 1 FROM subtree WHERE id = NEW.manager_id)
        INTO cycle_found;

      IF cycle_found THEN
        RAISE EXCEPTION 'admin user manager cannot create a hierarchy cycle'
          USING ERRCODE = '23514';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: enforce_profile_axis_governance(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_profile_axis_governance() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.axis = 'horizontal' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM profiles parent
      WHERE parent.id = NEW.vertical_profile_id
        AND parent.tenant_id = NEW.tenant_id
        AND parent.axis = 'vertical'
    ) THEN
      RAISE EXCEPTION 'horizontal profile must reference a vertical profile from the same tenant'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: enforce_trusted_device_tenant_governance(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_trusted_device_tenant_governance() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  owner_is_system_admin boolean;
  owner_tenant_id bigint;
BEGIN
  SELECT super_admin, tenant_id
    INTO owner_is_system_admin, owner_tenant_id
  FROM admin_users
  WHERE id = NEW.admin_user_id;

  IF owner_is_system_admin IS DISTINCT FROM TRUE AND NEW.tenant_id IS NULL THEN
    RAISE EXCEPTION 'trusted device tenant is required for account users'
      USING ERRCODE = '23514';
  END IF;

  IF owner_is_system_admin = TRUE AND NEW.tenant_id IS NOT NULL THEN
    RAISE EXCEPTION 'platform trusted device must not belong to a tenant'
      USING ERRCODE = '23514';
  END IF;

  IF owner_is_system_admin IS DISTINCT FROM TRUE AND owner_tenant_id IS DISTINCT FROM NEW.tenant_id THEN
    RAISE EXCEPTION 'trusted device tenant must match admin user tenant'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: raise_access_audit_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.raise_access_audit_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'access_audit_logs is append-only';
END; $$;


--
-- Name: raise_checkin_audit_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.raise_checkin_audit_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'checkin_audit_logs is append-only';
END; $$;


--
-- Name: raise_data_export_audit_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.raise_data_export_audit_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'data_export_audit_logs is append-only';
END;
$$;


--
-- Name: raise_habitation_audit_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.raise_habitation_audit_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'habitation_audit_logs is append-only';
END; $$;


--
-- Name: raise_lead_audit_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.raise_lead_audit_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'lead_audit_logs is append-only';
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: access_audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.access_audit_logs (
    id bigint NOT NULL,
    admin_user_id bigint,
    event_type character varying NOT NULL,
    result character varying NOT NULL,
    reason character varying,
    email character varying,
    ip inet,
    user_agent character varying,
    device_type character varying,
    browser character varying,
    platform character varying,
    path character varying,
    request_method character varying,
    controller_name character varying,
    action_name character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint
);


--
-- Name: access_audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.access_audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: access_audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.access_audit_logs_id_seq OWNED BY public.access_audit_logs.id;


--
-- Name: access_control_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.access_control_rules (
    id bigint NOT NULL,
    name character varying NOT NULL,
    rule_type character varying NOT NULL,
    scope_type character varying DEFAULT 'global'::character varying NOT NULL,
    profile_id bigint,
    admin_user_id bigint,
    created_by_id bigint,
    ip_value character varying NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: access_control_rules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.access_control_rules_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: access_control_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.access_control_rules_id_seq OWNED BY public.access_control_rules.id;


--
-- Name: account_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_memberships (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    invited_email character varying NOT NULL,
    primary_admin_user_id bigint,
    member_admin_user_id bigint,
    profile_id bigint NOT NULL,
    horizontal_profile_id bigint,
    manager_id bigint,
    rentals_manager_id bigint,
    acting_type integer,
    status integer DEFAULT 0 NOT NULL,
    invited_by_id bigint NOT NULL,
    invite_token_digest character varying,
    invite_sent_at timestamp(6) without time zone,
    invite_expires_at timestamp(6) without time zone,
    accepted_at timestamp(6) without time zone,
    revoked_at timestamp(6) without time zone,
    revoked_by_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: account_memberships_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.account_memberships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: account_memberships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.account_memberships_id_seq OWNED BY public.account_memberships.id;


--
-- Name: action_text_rich_texts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.action_text_rich_texts (
    id bigint NOT NULL,
    name character varying NOT NULL,
    body text,
    record_type character varying NOT NULL,
    record_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: action_text_rich_texts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.action_text_rich_texts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: action_text_rich_texts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.action_text_rich_texts_id_seq OWNED BY public.action_text_rich_texts.id;


--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id bigint NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.addresses (
    id bigint NOT NULL,
    addressable_type character varying NOT NULL,
    addressable_id bigint NOT NULL,
    tipo_endereco character varying,
    logradouro character varying,
    numero character varying,
    complemento character varying,
    bairro character varying,
    bairro_comercial character varying,
    cidade character varying,
    uf character varying(2),
    cep character varying(10),
    pais character varying DEFAULT 'Brasil'::character varying,
    latitude numeric(10,7),
    longitude numeric(10,7),
    imediacoes text[] DEFAULT '{}'::text[] NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: addresses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.addresses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: addresses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.addresses_id_seq OWNED BY public.addresses.id;


--
-- Name: admin_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_users (
    id bigint NOT NULL,
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    name character varying NOT NULL,
    role integer DEFAULT 0 NOT NULL,
    reset_password_token character varying,
    reset_password_sent_at timestamp(6) without time zone,
    remember_created_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    profile_id bigint,
    manager_id bigint,
    vista_id character varying,
    creci character varying,
    phone character varying,
    biography text,
    birth_date date,
    city character varying,
    acting_type integer,
    field_agent_enabled boolean DEFAULT false NOT NULL,
    default_store_id bigint,
    active boolean DEFAULT true NOT NULL,
    require_ip_allowlist boolean DEFAULT false NOT NULL,
    require_trusted_device boolean DEFAULT false NOT NULL,
    display_on_site boolean DEFAULT true NOT NULL,
    vista_import_batch_id bigint,
    vista_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    vista_agenciador boolean DEFAULT false NOT NULL,
    source_created_on date,
    source_departed_on date,
    last_login_at timestamp(6) without time zone,
    source_photo_path character varying,
    cpf_cnpj character varying,
    rg_ie character varying,
    nationality character varying,
    gender character varying,
    marital_status character varying,
    address_type character varying,
    street character varying,
    number character varying,
    complement character varying,
    neighborhood character varying,
    secondary_phone character varying,
    team_code character varying,
    capture_goal integer,
    rental_capture_goal integer,
    sales_goal_cents bigint,
    hierarchy_position integer,
    super_admin boolean DEFAULT false NOT NULL,
    leads_view_mode character varying,
    tenant_id bigint,
    horizontal_profile_id bigint,
    rentals_manager_id bigint,
    otp_secret character varying,
    otp_enabled_at timestamp(6) without time zone,
    otp_backup_codes jsonb DEFAULT '[]'::jsonb NOT NULL,
    otp_consumed_timestep integer,
    primary_admin_user_id bigint,
    contact_email character varying,
    CONSTRAINT admin_users_system_admin_outside_tenant CHECK (((super_admin = false) OR ((tenant_id IS NULL) AND (profile_id IS NULL) AND (horizontal_profile_id IS NULL) AND (manager_id IS NULL)))),
    CONSTRAINT admin_users_tenant_required_unless_system_admin CHECK (((super_admin = true) OR (tenant_id IS NOT NULL))),
    CONSTRAINT chk_admin_users_mirror_not_super_admin CHECK (((primary_admin_user_id IS NULL) OR (super_admin = false)))
);


--
-- Name: admin_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.admin_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: admin_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.admin_users_id_seq OWNED BY public.admin_users.id;


--
-- Name: ai_property_suggestions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_property_suggestions (
    id bigint NOT NULL,
    habitation_id bigint NOT NULL,
    admin_user_id bigint,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    generated_title character varying,
    generated_description text,
    generated_seo_keywords text,
    raw_response text,
    error_message text,
    applied_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ai_property_suggestions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ai_property_suggestions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ai_property_suggestions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ai_property_suggestions_id_seq OWNED BY public.ai_property_suggestions.id;


--
-- Name: appointments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appointments (
    id bigint NOT NULL,
    lead_id bigint,
    admin_user_id bigint NOT NULL,
    habitation_id bigint,
    title character varying NOT NULL,
    kind character varying DEFAULT 'visita'::character varying NOT NULL,
    starts_at timestamp(6) without time zone NOT NULL,
    ends_at timestamp(6) without time zone,
    location character varying,
    status character varying DEFAULT 'agendado'::character varying NOT NULL,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: appointments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.appointments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: appointments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.appointments_id_seq OWNED BY public.appointments.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: attribute_options; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attribute_options (
    id bigint NOT NULL,
    name character varying NOT NULL,
    category character varying NOT NULL,
    context character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    property_kinds jsonb DEFAULT '[]'::jsonb NOT NULL,
    "position" integer,
    description character varying,
    tenant_id bigint NOT NULL
);


--
-- Name: attribute_options_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.attribute_options_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: attribute_options_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.attribute_options_id_seq OWNED BY public.attribute_options.id;


--
-- Name: automation_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.automation_events (
    id bigint NOT NULL,
    lead_id bigint,
    name character varying NOT NULL,
    source character varying DEFAULT 'platform'::character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    idempotency_key character varying,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    occurred_at timestamp(6) without time zone NOT NULL,
    processed_at timestamp(6) without time zone,
    error_message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: automation_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.automation_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: automation_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.automation_events_id_seq OWNED BY public.automation_events.id;


--
-- Name: automation_execution_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.automation_execution_steps (
    id bigint NOT NULL,
    automation_execution_id bigint NOT NULL,
    node_id character varying NOT NULL,
    node_type character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    scheduled_for timestamp(6) without time zone,
    started_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    input jsonb DEFAULT '{}'::jsonb NOT NULL,
    output jsonb DEFAULT '{}'::jsonb NOT NULL,
    error_message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: automation_execution_steps_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.automation_execution_steps_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: automation_execution_steps_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.automation_execution_steps_id_seq OWNED BY public.automation_execution_steps.id;


--
-- Name: automation_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.automation_executions (
    id bigint NOT NULL,
    automation_workflow_id bigint NOT NULL,
    automation_workflow_version_id bigint NOT NULL,
    lead_id bigint,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    current_node_id character varying,
    idempotency_key character varying,
    context jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    failed_at timestamp(6) without time zone,
    error_message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    automation_event_id bigint,
    tenant_id bigint NOT NULL
);


--
-- Name: automation_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.automation_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: automation_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.automation_executions_id_seq OWNED BY public.automation_executions.id;


--
-- Name: automation_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.automation_rules (
    id bigint NOT NULL,
    name character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    trigger_event character varying NOT NULL,
    conditions jsonb DEFAULT '{}'::jsonb NOT NULL,
    actions jsonb DEFAULT '[]'::jsonb NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    last_run_at timestamp(6) without time zone,
    runs_count integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: automation_rules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.automation_rules_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: automation_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.automation_rules_id_seq OWNED BY public.automation_rules.id;


--
-- Name: automation_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.automation_runs (
    id bigint NOT NULL,
    automation_rule_id bigint NOT NULL,
    lead_id bigint,
    status character varying DEFAULT 'executed'::character varying NOT NULL,
    scheduled_at timestamp(6) without time zone,
    executed_at timestamp(6) without time zone,
    result jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    automation_event_id bigint
);


--
-- Name: automation_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.automation_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: automation_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.automation_runs_id_seq OWNED BY public.automation_runs.id;


--
-- Name: automation_webhook_deliveries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.automation_webhook_deliveries (
    id bigint NOT NULL,
    automation_event_id bigint,
    automation_run_id bigint,
    automation_execution_step_id bigint,
    lead_id bigint,
    url character varying NOT NULL,
    http_method character varying DEFAULT 'post'::character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    response_code integer,
    request_headers jsonb DEFAULT '{}'::jsonb NOT NULL,
    request_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    response_body text,
    error_message text,
    sent_at timestamp(6) without time zone,
    responded_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: automation_webhook_deliveries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.automation_webhook_deliveries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: automation_webhook_deliveries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.automation_webhook_deliveries_id_seq OWNED BY public.automation_webhook_deliveries.id;


--
-- Name: automation_workflow_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.automation_workflow_versions (
    id bigint NOT NULL,
    automation_workflow_id bigint NOT NULL,
    version_number integer NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    definition jsonb DEFAULT '{}'::jsonb NOT NULL,
    validation_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_by_id bigint,
    published_by_id bigint,
    published_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: automation_workflow_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.automation_workflow_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: automation_workflow_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.automation_workflow_versions_id_seq OWNED BY public.automation_workflow_versions.id;


--
-- Name: automation_workflows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.automation_workflows (
    id bigint NOT NULL,
    name character varying NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    active_version_id bigint,
    created_by_id bigint,
    last_activated_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: automation_workflows_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.automation_workflows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: automation_workflows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.automation_workflows_id_seq OWNED BY public.automation_workflows.id;


--
-- Name: banners; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.banners (
    id bigint NOT NULL,
    title character varying,
    description text,
    link_url character varying,
    link_text character varying,
    active boolean,
    display_order integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    positions character varying[] DEFAULT '{}'::character varying[]
);


--
-- Name: banners_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.banners_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: banners_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.banners_id_seq OWNED BY public.banners.id;


--
-- Name: captacao_goals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.captacao_goals (
    id bigint NOT NULL,
    year integer NOT NULL,
    kind integer NOT NULL,
    target integer NOT NULL,
    foco_regiao character varying,
    foco_valor_min numeric(12,2),
    foco_valor_max numeric(12,2),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL
);


--
-- Name: captacao_goals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.captacao_goals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: captacao_goals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.captacao_goals_id_seq OWNED BY public.captacao_goals.id;


--
-- Name: captacoes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.captacoes (
    id bigint NOT NULL,
    corretor_id bigint NOT NULL,
    step character varying DEFAULT 'intro'::character varying NOT NULL,
    completed boolean DEFAULT false NOT NULL,
    published_on_site boolean DEFAULT false NOT NULL,
    submitted_at timestamp(6) without time zone,
    property_kind integer DEFAULT 0 NOT NULL,
    modalidade integer,
    proprietario_nome character varying,
    proprietario_telefone character varying,
    proprietario_cpf_cnpj character varying,
    proprietario_email character varying,
    proprietario_cidade character varying,
    zip_code character varying,
    street character varying,
    street_number character varying,
    neighborhood character varying,
    city character varying,
    state character varying(2),
    edificio_nome character varying,
    unidade_numero character varying,
    latitude numeric(10,6),
    longitude numeric(10,6),
    dormitorios integer,
    suites integer,
    demi_suites integer,
    salas integer,
    banheiros integer,
    vagas_garagem integer,
    area_privativa numeric(10,2),
    area_total numeric(10,2),
    ocupacao character varying,
    estado_imovel character varying,
    situacao_imovel character varying,
    precisa_reforma boolean DEFAULT false NOT NULL,
    sacada boolean DEFAULT false NOT NULL,
    terraco boolean DEFAULT false NOT NULL,
    dependencia_empregada boolean DEFAULT false NOT NULL,
    andares_total integer,
    aptos_por_andar integer,
    distancia_praia numeric(6,2),
    caracteristicas_imovel character varying[] DEFAULT '{}'::character varying[],
    caracteristicas_predio character varying[] DEFAULT '{}'::character varying[],
    outras_taxas character varying[] DEFAULT '{}'::character varying[],
    aceita_permuta character varying[] DEFAULT '{}'::character varying[],
    dias_visitas character varying[] DEFAULT '{}'::character varying[],
    valor_venda numeric(12,2),
    valor_locacao numeric(10,2),
    valor_condominio numeric(10,2),
    valor_iptu numeric(10,2),
    saldo_devedor numeric(12,2),
    cidade_permuta character varying,
    aceita_parcelamento character varying,
    motivo_venda character varying,
    chaves_com character varying,
    senha_imovel character varying,
    senha_portaria character varying,
    observacoes text,
    extras jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: captacoes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.captacoes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: captacoes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.captacoes_id_seq OWNED BY public.captacoes.id;


--
-- Name: check_ins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.check_ins (
    id bigint NOT NULL,
    admin_user_id bigint NOT NULL,
    store_id bigint NOT NULL,
    store_shift_id bigint,
    checked_in_at timestamp(6) without time zone NOT NULL,
    checked_out_at timestamp(6) without time zone,
    status integer DEFAULT 0 NOT NULL,
    checkin_accuracy_meters integer,
    checkout_accuracy_meters integer,
    checkin_ip inet,
    checkout_ip inet,
    device_info jsonb DEFAULT '{}'::jsonb,
    out_of_radius_since timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    checkin_location public.geography(Point,4326),
    checkout_location public.geography(Point,4326),
    suspicious boolean DEFAULT false NOT NULL,
    suspicious_reasons jsonb DEFAULT '[]'::jsonb,
    fingerprint_hash character varying,
    tenant_id bigint NOT NULL,
    turno character varying,
    status_chegada character varying
);


--
-- Name: check_ins_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.check_ins_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: check_ins_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.check_ins_id_seq OWNED BY public.check_ins.id;


--
-- Name: checkin_audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.checkin_audit_logs (
    id bigint NOT NULL,
    check_in_id bigint,
    admin_user_id bigint,
    actor_admin_user_id bigint,
    action character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    ip inet,
    created_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: checkin_audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.checkin_audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: checkin_audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.checkin_audit_logs_id_seq OWNED BY public.checkin_audit_logs.id;


--
-- Name: client_interactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.client_interactions (
    id bigint NOT NULL,
    vista_import_batch_id bigint,
    source_table character varying NOT NULL,
    source_key character varying NOT NULL,
    proprietor_id bigint,
    habitation_id bigint,
    admin_user_id bigint,
    vista_client_code character varying,
    vista_habitation_code character varying,
    vista_agent_code character varying,
    subject character varying,
    body text,
    interaction_type character varying,
    activity_type_id character varying,
    occurred_at timestamp(6) without time zone,
    return_at timestamp(6) without time zone,
    pending boolean DEFAULT false NOT NULL,
    automatic boolean DEFAULT false NOT NULL,
    lead boolean DEFAULT false NOT NULL,
    launch boolean DEFAULT false NOT NULL,
    acceptance character varying,
    visit_status character varying,
    lost_reason character varying,
    capture_vehicle character varying,
    proposal_value_cents bigint,
    business_id character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    crm_contact_id bigint
);


--
-- Name: client_interactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.client_interactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: client_interactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.client_interactions_id_seq OWNED BY public.client_interactions.id;


--
-- Name: client_property_interests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.client_property_interests (
    id bigint NOT NULL,
    vista_import_batch_id bigint,
    source_table character varying NOT NULL,
    source_key character varying NOT NULL,
    proprietor_id bigint,
    habitation_id bigint,
    admin_user_id bigint,
    vista_client_code character varying,
    vista_habitation_code character varying,
    vista_agent_code character varying,
    interest_type character varying,
    status character varying,
    notes text,
    selected boolean DEFAULT false NOT NULL,
    awaited boolean DEFAULT false NOT NULL,
    lead boolean DEFAULT false NOT NULL,
    started_at timestamp(6) without time zone,
    ended_at timestamp(6) without time zone,
    consulted_at timestamp(6) without time zone,
    last_search_at timestamp(6) without time zone,
    business_id character varying,
    criteria jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    crm_contact_id bigint,
    lead_id bigint
);


--
-- Name: client_property_interests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.client_property_interests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: client_property_interests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.client_property_interests_id_seq OWNED BY public.client_property_interests.id;


--
-- Name: constructors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.constructors (
    id bigint NOT NULL,
    name character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    website_url character varying
);


--
-- Name: constructors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.constructors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: constructors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.constructors_id_seq OWNED BY public.constructors.id;


--
-- Name: contact_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contact_settings (
    id bigint NOT NULL,
    whatsapp_primary character varying,
    whatsapp_secondary character varying,
    phone character varying,
    email_primary character varying,
    email_commercial character varying,
    address text,
    business_hours text,
    facebook_url character varying,
    instagram_url character varying,
    youtube_url character varying,
    linkedin_url character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: contact_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.contact_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contact_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.contact_settings_id_seq OWNED BY public.contact_settings.id;


--
-- Name: crm_appointments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_appointments (
    id bigint NOT NULL,
    vista_import_batch_id bigint,
    source_table character varying NOT NULL,
    source_key character varying NOT NULL,
    proprietor_id bigint,
    habitation_id bigint,
    admin_user_id bigint,
    vista_client_code character varying,
    vista_habitation_code character varying,
    vista_agent_code character varying,
    title character varying,
    description text,
    appointment_type character varying,
    priority character varying,
    location character varying,
    starts_at timestamp(6) without time zone,
    ends_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    created_in_source_at timestamp(6) without time zone,
    task boolean DEFAULT false NOT NULL,
    completed boolean DEFAULT false NOT NULL,
    all_day boolean DEFAULT false NOT NULL,
    private boolean DEFAULT false NOT NULL,
    deleted boolean DEFAULT false NOT NULL,
    visit_status character varying,
    google_calendar_id character varying,
    business_id character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    crm_contact_id bigint,
    reminder_minutes integer,
    sms_client boolean DEFAULT false NOT NULL,
    sms_owner boolean DEFAULT false NOT NULL,
    synced_with_source boolean DEFAULT false NOT NULL,
    source_updated_at timestamp(6) without time zone
);


--
-- Name: crm_appointments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.crm_appointments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: crm_appointments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.crm_appointments_id_seq OWNED BY public.crm_appointments.id;


--
-- Name: crm_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crm_contacts (
    id bigint NOT NULL,
    vista_import_batch_id bigint,
    vista_code character varying NOT NULL,
    name character varying NOT NULL,
    email character varying,
    phone_primary character varying,
    mobile_phone character varying,
    residential_phone character varying,
    business_phone character varying,
    cpf_cnpj character varying,
    rg_ie character varying,
    contact_type character varying,
    is_client boolean DEFAULT false NOT NULL,
    is_owner boolean DEFAULT false NOT NULL,
    is_buyer boolean DEFAULT false NOT NULL,
    is_referenced_owner boolean DEFAULT false NOT NULL,
    capture_vehicle character varying,
    registered_at timestamp(6) without time zone,
    notes text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    source_status character varying,
    source_updated_at timestamp(6) without time zone,
    potential_value_cents bigint,
    favorite boolean DEFAULT false NOT NULL,
    restricted boolean DEFAULT false NOT NULL,
    receive_information boolean DEFAULT false NOT NULL,
    show_email_to_client boolean DEFAULT false NOT NULL,
    show_phone_on_web boolean DEFAULT false NOT NULL
);


--
-- Name: crm_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.crm_contacts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: crm_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.crm_contacts_id_seq OWNED BY public.crm_contacts.id;


--
-- Name: data_export_audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_export_audit_logs (
    id bigint NOT NULL,
    admin_user_id bigint,
    export_type character varying NOT NULL,
    resource_name character varying NOT NULL,
    format character varying NOT NULL,
    record_count integer DEFAULT 0 NOT NULL,
    selected_count integer DEFAULT 0 NOT NULL,
    filename character varying,
    filters jsonb DEFAULT '{}'::jsonb NOT NULL,
    fields jsonb DEFAULT '[]'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    ip inet,
    user_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: data_export_audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.data_export_audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: data_export_audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.data_export_audit_logs_id_seq OWNED BY public.data_export_audit_logs.id;


--
-- Name: distribution_rule_agents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.distribution_rule_agents (
    id bigint NOT NULL,
    distribution_rule_id bigint NOT NULL,
    admin_user_id bigint NOT NULL,
    weight integer DEFAULT 1,
    last_lead_received_at timestamp(6) without time zone,
    "position" integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: distribution_rule_agents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.distribution_rule_agents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: distribution_rule_agents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.distribution_rule_agents_id_seq OWNED BY public.distribution_rule_agents.id;


--
-- Name: distribution_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.distribution_rules (
    id bigint NOT NULL,
    name character varying NOT NULL,
    business_type integer DEFAULT 0,
    source_meta boolean DEFAULT false,
    source_webhook boolean DEFAULT false,
    source_portal boolean DEFAULT false,
    meta_forms jsonb DEFAULT '[]'::jsonb,
    webhook_tags jsonb DEFAULT '[]'::jsonb,
    custom_filters jsonb DEFAULT '[]'::jsonb,
    distribution_mode integer DEFAULT 0,
    pocket_active boolean DEFAULT false,
    pocket_time integer DEFAULT 30,
    represamento_active boolean DEFAULT false,
    represamento_schedule jsonb DEFAULT '{}'::jsonb,
    active boolean DEFAULT true,
    min_price numeric(15,2),
    max_price numeric(15,2),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    source_site boolean DEFAULT false,
    auto_add_forms boolean DEFAULT false,
    notify_whatsapp boolean DEFAULT false,
    notify_email boolean DEFAULT false,
    notify_webhook boolean DEFAULT false,
    meta_page_ids jsonb DEFAULT '[]'::jsonb,
    neighborhoods jsonb DEFAULT '[]'::jsonb,
    webhook_url character varying,
    require_active_checkin boolean DEFAULT false NOT NULL,
    require_inside_radius boolean DEFAULT false NOT NULL,
    exclude_suspicious_checkins boolean DEFAULT true NOT NULL,
    checkin_store_id bigint,
    require_active_shift boolean DEFAULT false NOT NULL,
    checkin_store_ids bigint[] DEFAULT '{}'::bigint[] NOT NULL,
    notify_push boolean DEFAULT false NOT NULL,
    notify_webhook_urls jsonb DEFAULT '[]'::jsonb NOT NULL,
    tenant_id bigint NOT NULL,
    hierarchy_manager_ids jsonb DEFAULT '[]'::jsonb NOT NULL,
    auto_update_agents_enabled boolean DEFAULT false NOT NULL,
    auto_update_trigger character varying[] DEFAULT '{sorteio}'::character varying[] NOT NULL,
    auto_update_shuffle_agents boolean DEFAULT false NOT NULL
);


--
-- Name: distribution_rules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.distribution_rules_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: distribution_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.distribution_rules_id_seq OWNED BY public.distribution_rules.id;


--
-- Name: email_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_settings (
    id bigint NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    smtp_address character varying,
    smtp_port integer DEFAULT 587 NOT NULL,
    smtp_domain character varying,
    smtp_user_name character varying,
    smtp_password text,
    smtp_authentication character varying DEFAULT 'plain'::character varying,
    smtp_enable_starttls_auto boolean DEFAULT true NOT NULL,
    from_name character varying,
    from_email character varying,
    reply_to character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint
);


--
-- Name: email_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.email_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: email_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.email_settings_id_seq OWNED BY public.email_settings.id;


--
-- Name: error_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.error_events (
    id bigint NOT NULL,
    fingerprint character varying NOT NULL,
    exception_class character varying,
    message text,
    backtrace text,
    source character varying,
    severity character varying DEFAULT 'error'::character varying NOT NULL,
    tenant_id bigint,
    context jsonb DEFAULT '{}'::jsonb NOT NULL,
    occurrences_count integer DEFAULT 1 NOT NULL,
    first_seen_at timestamp(6) without time zone,
    last_seen_at timestamp(6) without time zone,
    last_alerted_at timestamp(6) without time zone,
    resolved_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: error_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.error_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: error_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.error_events_id_seq OWNED BY public.error_events.id;


--
-- Name: habitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.habitations (
    id bigint NOT NULL,
    codigo character varying NOT NULL,
    slug character varying,
    categoria character varying,
    status character varying,
    situacao character varying,
    tipo character varying,
    codigo_empreendimento character varying,
    nome_empreendimento character varying,
    tipo_endereco character varying,
    endereco character varying,
    numero character varying,
    complemento character varying,
    bairro character varying,
    cidade character varying,
    uf character varying(2),
    cep character varying(10),
    pais character varying DEFAULT 'Brasil'::character varying,
    latitude numeric(10,7),
    longitude numeric(10,7),
    dormitorios_qtd integer DEFAULT 0,
    suites_qtd integer DEFAULT 0,
    banheiros_qtd integer DEFAULT 0,
    vagas_qtd integer DEFAULT 0,
    elevadores_qtd integer DEFAULT 0,
    area_privativa_m2 numeric(10,2),
    area_total_m2 numeric(10,2),
    area_terreno_m2 numeric(10,2),
    area_util_m2 numeric(10,2),
    valor_venda_cents bigint,
    valor_locacao_cents bigint,
    valor_condominio_cents bigint,
    valor_iptu_cents bigint,
    valor_por_m2_cents bigint,
    caracteristicas jsonb DEFAULT '{}'::jsonb,
    infra_estrutura jsonb DEFAULT '{}'::jsonb,
    destaque_localizacao jsonb DEFAULT '{}'::jsonb,
    pictures jsonb DEFAULT '[]'::jsonb,
    videos jsonb DEFAULT '[]'::jsonb,
    plantas jsonb DEFAULT '[]'::jsonb,
    descricao_web text,
    descricao_interna text,
    titulo_anuncio character varying,
    observacoes text,
    corretor_nome character varying,
    corretor_telefone character varying,
    corretor_email character varying,
    proprietario_codigo character varying,
    exibir_no_site_flag boolean DEFAULT false,
    destaque_web_flag boolean DEFAULT false,
    lancamento_flag boolean DEFAULT false,
    aceita_permuta_flag boolean DEFAULT false,
    aceita_financiamento_flag boolean DEFAULT false,
    mobiliado_flag boolean DEFAULT false,
    data_atualizacao_crm timestamp(6) without time zone,
    data_cadastro_crm timestamp(6) without time zone,
    status_vista character varying,
    meta_title character varying,
    meta_description text,
    meta_keywords character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    piscina_flag boolean DEFAULT false,
    lavabo_flag boolean DEFAULT false,
    varanda_gourmet_flag boolean DEFAULT false,
    bairro_comercial character varying,
    bloco character varying,
    lote character varying,
    imediacoes text,
    banheiro_social_qtd integer,
    decorado_flag boolean,
    aptos_andar integer,
    aptos_edificio integer,
    garden_flag boolean,
    quadra_mar_flag boolean,
    sem_mobilia_flag boolean,
    valor_venda_anterior_cents bigint,
    valor_total_aluguel_cents bigint,
    valor_promocional_cents bigint,
    construtora character varying,
    proprietario character varying,
    inscricao_imobiliaria character varying,
    descricao_empreendimento text,
    caracteristica_unica text[] DEFAULT '{}'::text[],
    terceira_avenida_flag boolean,
    arriba_flag boolean,
    avenida_brasil_flag boolean,
    bairro_fazenda_itajai_flag boolean,
    balneario_picarras_flag boolean,
    barra_flag boolean,
    barra_norte_flag boolean,
    barra_sul_flag boolean,
    cabecudas_flag boolean,
    camboriu_flag boolean,
    centro_flag boolean,
    estaleirinho_flag boolean,
    frente_mar_avenida_atlantica_flag boolean,
    itajai_flag boolean,
    itapema_flag boolean,
    nacoes_flag boolean,
    pioneiros_flag boolean,
    praia_brava_flag boolean,
    praia_dos_amores_flag boolean,
    vista_frente_mar_flag boolean,
    festival_salute_flag boolean,
    exibir_no_site_salute_flag boolean,
    categoria_grupo character varying,
    data_entrega date,
    tour_virtual character varying,
    fotos_empreendimento jsonb,
    codigo_corretor character varying,
    captador_account_id character varying,
    agenciador character varying,
    codigo_dwv character varying,
    imovel_dwv character varying,
    tem_placa_flag boolean,
    photo_ids_order jsonb DEFAULT '[]'::jsonb,
    last_sync_at timestamp(6) without time zone,
    last_sync_status character varying,
    last_sync_message text,
    admin_user_id bigint,
    constructor_id bigint,
    proprietario_celular character varying,
    proprietario_telefone_comercial character varying,
    proprietario_telefone_residencial character varying,
    proprietario_email character varying,
    face character varying,
    perfil_construcao character varying,
    tipo_vaga character varying,
    hidromassagem_qtd integer,
    exclusivo_flag boolean,
    ocupacao_status character varying,
    estado_conservacao character varying,
    andar integer,
    ano_construcao integer,
    demi_suites_qtd integer,
    numero_box character varying,
    dimensoes_terreno character varying,
    topografia character varying,
    foto_classificacao character varying,
    podcast_url character varying,
    captador_commission_percentage numeric(5,2),
    broker_commission_percentage numeric(5,2),
    salute_rental_management_flag boolean DEFAULT false NOT NULL,
    key_location character varying,
    key_location_notes character varying,
    proprietor_id bigint,
    home_corporate_flag boolean DEFAULT false NOT NULL,
    home_corporate_position integer,
    valor_aceito_permuta_cents bigint,
    aceita_permuta_veiculo_flag boolean DEFAULT false NOT NULL,
    aceita_permuta_imovel_flag boolean DEFAULT false NOT NULL,
    aceita_permuta_outros_flag boolean DEFAULT false NOT NULL,
    tipo_veiculo_aceito_permuta character varying,
    ano_minimo_veiculo_aceito_permuta integer,
    permuta_valor_cents bigint,
    permuta_localizacao character varying,
    permuta_dormitorios_qtd integer,
    permuta_suites_qtd integer,
    permuta_garagens_qtd integer,
    matricula_imovel character varying,
    zona character varying,
    aceita_doacao_flag boolean DEFAULT false NOT NULL,
    condicoes_negociacao text,
    valor_locacao_anterior_cents bigint,
    saldo_devedor_cents bigint,
    numero_prestacoes integer,
    responsavel_reserva character varying,
    zelador_nome character varying,
    zelador_telefone character varying,
    observacoes_visitas text,
    regiao_foco character varying,
    tipo_fachada character varying,
    andares_qtd integer,
    publicar_imovelweb_2 boolean DEFAULT false NOT NULL,
    publicar_netimoveis_2 boolean DEFAULT false NOT NULL,
    publicar_lais_ai boolean DEFAULT false NOT NULL,
    publicar_loft boolean DEFAULT false NOT NULL,
    publicar_chaves_na_mao boolean DEFAULT false NOT NULL,
    publicar_casa_mineira boolean DEFAULT false NOT NULL,
    publicar_imovelweb boolean DEFAULT false NOT NULL,
    publicar_viva_real_vrsync boolean DEFAULT false NOT NULL,
    destaque_chaves_na_mao character varying,
    periodo_locacao_chaves_na_mao character varying,
    modelo_casa_mineira character varying,
    tipo_publicacao_viva_real character varying,
    divulgar_endereco_viva_real character varying,
    tipo_publicacao_imovelweb character varying,
    mostrar_mapa_imovelweb character varying,
    tipo_publicacao_imovelweb_2 character varying,
    mostrar_mapa_imovelweb_2 character varying,
    publicar_zapimoveis boolean DEFAULT false NOT NULL,
    intake_origin character varying,
    intake_status character varying,
    submitted_for_review_at timestamp(6) without time zone,
    admin_reviewed_by_id bigint,
    admin_reviewed_at timestamp(6) without time zone,
    admin_review_notes text,
    broker_released_at timestamp(6) without time zone,
    photo_flow_choice character varying,
    photo_session_requested_at timestamp(6) without time zone,
    photo_session_url character varying,
    aceita_parcelamento_flag boolean DEFAULT false NOT NULL,
    salute_rental_management_answer character varying,
    aceita_permuta_answer character varying,
    intake_step character varying DEFAULT 'intro'::character varying NOT NULL,
    motivo_venda character varying,
    intake_modalidade character varying,
    intake_group_uuid character varying,
    vista_import_batch_id bigint,
    vista_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    vista_codigo character varying,
    vista_imo_codigo character varying,
    vista_imo_placa character varying,
    vista_referencia_externa character varying,
    salas_qtd integer,
    varandas_qtd integer,
    use_development_photos_flag boolean DEFAULT false NOT NULL,
    valor_comissao_cents bigint,
    valor_livre_proprietario_cents bigint,
    motivo_suspensao text,
    valor_alugado_terceiros_cents bigint,
    valor_vendido_terceiros_cents bigint,
    site_hidden_photo_ids jsonb DEFAULT '[]'::jsonb NOT NULL,
    dwv_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    rental_guarantee_method character varying,
    permuta_valor_percentual integer,
    frente_terreno_m numeric(10,2),
    fundo_terreno_m numeric(10,2),
    photo_environment_assignments jsonb DEFAULT '{}'::jsonb NOT NULL,
    photo_calendar_provider character varying,
    photo_calendar_event_id character varying,
    photo_calendar_error text,
    photo_calendar_synced_at timestamp(6) without time zone,
    admin_review_return_reason text,
    tenant_id bigint NOT NULL,
    quadra character varying,
    permuta_veiculo_valor_cents integer,
    permuta_outros_valor_cents integer,
    permuta_outros_descricao text,
    public_map_display_mode character varying DEFAULT 'inherit'::character varying NOT NULL,
    public_street_view_mode character varying DEFAULT 'inherit'::character varying NOT NULL
);


--
-- Name: featured_properties_view; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.featured_properties_view AS
 SELECT id,
    codigo,
    slug,
    categoria,
    status,
    cidade,
    bairro,
    titulo_anuncio,
    valor_venda_cents,
    valor_locacao_cents,
    dormitorios_qtd,
    suites_qtd,
    vagas_qtd,
    area_total_m2,
    pictures,
    destaque_web_flag,
    lancamento_flag,
    data_atualizacao_crm,
    updated_at
   FROM public.habitations
  WHERE ((exibir_no_site_flag = true) AND (destaque_web_flag = true) AND (((status)::text = 'Venda'::text) OR ((status)::text = 'Locação'::text)))
  ORDER BY data_atualizacao_crm DESC NULLS LAST
 LIMIT 100
  WITH NO DATA;


--
-- Name: footer_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.footer_links (
    id bigint NOT NULL,
    label character varying,
    url character varying,
    "position" integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    footer_setting_id bigint NOT NULL
);


--
-- Name: footer_links_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.footer_links_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: footer_links_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.footer_links_id_seq OWNED BY public.footer_links.id;


--
-- Name: footer_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.footer_settings (
    id bigint NOT NULL,
    about_title character varying,
    about_text text,
    links_title character varying,
    stores_title character varying,
    contact_title character varying,
    social_title character varying,
    whatsapp character varying,
    email character varying,
    copyright_text character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: footer_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.footer_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: footer_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.footer_settings_id_seq OWNED BY public.footer_settings.id;


--
-- Name: footer_social_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.footer_social_links (
    id bigint NOT NULL,
    platform character varying,
    url character varying,
    enabled boolean,
    "position" integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    footer_setting_id bigint NOT NULL
);


--
-- Name: footer_social_links_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.footer_social_links_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: footer_social_links_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.footer_social_links_id_seq OWNED BY public.footer_social_links.id;


--
-- Name: footer_stores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.footer_stores (
    id bigint NOT NULL,
    name character varying,
    address character varying,
    zip_code character varying,
    creci character varying,
    phone character varying,
    "position" integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    footer_setting_id bigint NOT NULL
);


--
-- Name: footer_stores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.footer_stores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: footer_stores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.footer_stores_id_seq OWNED BY public.footer_stores.id;


--
-- Name: friendly_id_slugs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.friendly_id_slugs (
    id bigint NOT NULL,
    slug character varying NOT NULL,
    sluggable_id integer NOT NULL,
    sluggable_type character varying(50),
    scope character varying,
    created_at timestamp(6) without time zone
);


--
-- Name: friendly_id_slugs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.friendly_id_slugs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: friendly_id_slugs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.friendly_id_slugs_id_seq OWNED BY public.friendly_id_slugs.id;


--
-- Name: google_calendar_integration_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.google_calendar_integration_settings (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    calendar_id character varying,
    default_duration_minutes integer DEFAULT 60 NOT NULL,
    service_account_json text,
    last_synced_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: google_calendar_integration_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.google_calendar_integration_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: google_calendar_integration_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.google_calendar_integration_settings_id_seq OWNED BY public.google_calendar_integration_settings.id;


--
-- Name: google_maps_integration_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.google_maps_integration_settings (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    api_key text,
    default_display_mode character varying DEFAULT 'approximate'::character varying NOT NULL,
    approximate_radius_meters integer DEFAULT 220 NOT NULL,
    default_zoom integer DEFAULT 15 NOT NULL,
    satellite_enabled boolean DEFAULT true NOT NULL,
    street_view_enabled boolean DEFAULT true NOT NULL,
    external_link_enabled boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: google_maps_integration_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.google_maps_integration_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: google_maps_integration_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.google_maps_integration_settings_id_seq OWNED BY public.google_maps_integration_settings.id;


--
-- Name: habitation_audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.habitation_audit_logs (
    id bigint NOT NULL,
    habitation_id bigint NOT NULL,
    admin_user_id bigint,
    action character varying NOT NULL,
    source character varying DEFAULT 'admin'::character varying NOT NULL,
    changed_fields text[] DEFAULT '{}'::text[] NOT NULL,
    changeset jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    ip inet,
    user_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: habitation_audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.habitation_audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: habitation_audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.habitation_audit_logs_id_seq OWNED BY public.habitation_audit_logs.id;


--
-- Name: habitation_broker_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.habitation_broker_assignments (
    id bigint NOT NULL,
    habitation_id bigint NOT NULL,
    admin_user_id bigint NOT NULL,
    role character varying,
    commission_type character varying,
    commission_value numeric(10,2),
    observations text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    vista_import_batch_id bigint,
    vista_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    vista_source_key character varying,
    source_created_at timestamp(6) without time zone,
    sale_commission_percentage numeric(10,2),
    rental_commission_percentage numeric(10,2),
    rental_cancellation_commission_percentage numeric(10,2),
    sale_commission_cents bigint,
    rental_commission_cents bigint,
    rental_cancellation_commission_cents bigint
);


--
-- Name: habitation_broker_assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.habitation_broker_assignments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: habitation_broker_assignments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.habitation_broker_assignments_id_seq OWNED BY public.habitation_broker_assignments.id;


--
-- Name: habitation_exports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.habitation_exports (
    id bigint NOT NULL,
    admin_user_id bigint NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    progress integer DEFAULT 0 NOT NULL,
    filename character varying,
    record_count integer DEFAULT 0 NOT NULL,
    fields jsonb DEFAULT '[]'::jsonb NOT NULL,
    source_ids jsonb DEFAULT '[]'::jsonb NOT NULL,
    col_sep character varying DEFAULT ';'::character varying NOT NULL,
    error_message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: habitation_exports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.habitation_exports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: habitation_exports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.habitation_exports_id_seq OWNED BY public.habitation_exports.id;


--
-- Name: habitation_interactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.habitation_interactions (
    id bigint NOT NULL,
    vista_import_batch_id bigint,
    source_table character varying NOT NULL,
    source_key character varying NOT NULL,
    habitation_id bigint,
    proprietor_id bigint,
    admin_user_id bigint,
    vista_habitation_code character varying,
    vista_client_code character varying,
    vista_agent_code character varying,
    subject character varying,
    body text,
    interaction_type character varying,
    activity_type_id character varying,
    occurred_at timestamp(6) without time zone,
    started_at timestamp(6) without time zone,
    pending boolean DEFAULT false NOT NULL,
    automatic boolean DEFAULT false NOT NULL,
    private boolean DEFAULT false NOT NULL,
    proposal boolean DEFAULT false NOT NULL,
    status character varying,
    advertised character varying,
    published_vehicle character varying,
    key_requester character varying,
    proposal_value_cents bigint,
    business_id character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    crm_contact_id bigint
);


--
-- Name: habitation_interactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.habitation_interactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: habitation_interactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.habitation_interactions_id_seq OWNED BY public.habitation_interactions.id;


--
-- Name: habitation_photo_shares; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.habitation_photo_shares (
    id bigint NOT NULL,
    habitation_id bigint NOT NULL,
    admin_user_id bigint,
    token character varying NOT NULL,
    photo_ids jsonb DEFAULT '[]'::jsonb NOT NULL,
    expires_at timestamp(6) without time zone,
    last_viewed_at timestamp(6) without time zone,
    views_count integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    picture_urls jsonb DEFAULT '[]'::jsonb NOT NULL
);


--
-- Name: habitation_photo_shares_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.habitation_photo_shares_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: habitation_photo_shares_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.habitation_photo_shares_id_seq OWNED BY public.habitation_photo_shares.id;


--
-- Name: habitation_share_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.habitation_share_links (
    id bigint NOT NULL,
    habitation_id bigint NOT NULL,
    admin_user_id bigint NOT NULL,
    token character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    last_clicked_at timestamp(6) without time zone,
    clicks_count integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: habitation_share_links_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.habitation_share_links_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: habitation_share_links_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.habitation_share_links_id_seq OWNED BY public.habitation_share_links.id;


--
-- Name: habitations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.habitations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: habitations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.habitations_id_seq OWNED BY public.habitations.id;


--
-- Name: home_hero_slides; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.home_hero_slides (
    id bigint NOT NULL,
    home_setting_id bigint NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    alt_text character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: home_hero_slides_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.home_hero_slides_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: home_hero_slides_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.home_hero_slides_id_seq OWNED BY public.home_hero_slides.id;


--
-- Name: home_section_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.home_section_items (
    id bigint NOT NULL,
    home_section_id bigint NOT NULL,
    title character varying,
    description text,
    active boolean,
    display_order integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: home_section_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.home_section_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: home_section_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.home_section_items_id_seq OWNED BY public.home_section_items.id;


--
-- Name: home_sections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.home_sections (
    id bigint NOT NULL,
    section_type integer,
    title character varying,
    subtitle text,
    active boolean,
    display_order integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    order_position integer DEFAULT 0,
    property_filters jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: home_sections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.home_sections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: home_sections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.home_sections_id_seq OWNED BY public.home_sections.id;


--
-- Name: home_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.home_settings (
    id bigint NOT NULL,
    hero_title text,
    hero_subtitle text,
    cta_title text,
    cta_subtitle text,
    services_active boolean,
    why_choose_active boolean,
    cta_contact_active boolean,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    hero_cta_text character varying,
    hero_cta_link character varying,
    overlay_opacity numeric,
    overlay_color character varying,
    hero_button_color character varying,
    hero_button_text_color character varying,
    search_filter_background_color character varying,
    search_filter_background_opacity numeric(3,2),
    search_filter_border_color character varying,
    search_filter_text_color character varying,
    search_filter_field_background_color character varying,
    search_filter_field_background_opacity numeric(3,2),
    search_filter_backdrop_blur integer,
    search_filter_border_enabled boolean DEFAULT true NOT NULL,
    search_filter_border_opacity numeric(3,2),
    search_filter_border_radius integer,
    hero_title_font_size integer,
    hero_subtitle_font_size integer
);


--
-- Name: home_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.home_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: home_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.home_settings_id_seq OWNED BY public.home_settings.id;


--
-- Name: inbound_webhook_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inbound_webhook_tokens (
    id bigint NOT NULL,
    admin_user_id bigint NOT NULL,
    token character varying NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    last_received_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: inbound_webhook_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.inbound_webhook_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inbound_webhook_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.inbound_webhook_tokens_id_seq OWNED BY public.inbound_webhook_tokens.id;


--
-- Name: landing_pages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.landing_pages (
    id bigint NOT NULL,
    title character varying,
    slug character varying,
    filter_params jsonb DEFAULT '{}'::jsonb,
    meta_title character varying,
    meta_description text,
    content text,
    active boolean,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: landing_pages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.landing_pages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: landing_pages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.landing_pages_id_seq OWNED BY public.landing_pages.id;


--
-- Name: layout_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.layout_settings (
    id bigint NOT NULL,
    primary_color character varying,
    secondary_color character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    site_name character varying,
    accent_color character varying,
    admin_primary_color character varying DEFAULT '#365F8F'::character varying NOT NULL,
    admin_surface_color character varying DEFAULT '#FFFFFF'::character varying NOT NULL,
    admin_header_color character varying DEFAULT '#EEF2F7'::character varying NOT NULL,
    admin_ink_color character varying DEFAULT '#1F2733'::character varying NOT NULL,
    admin_area_name character varying DEFAULT 'Plataforma'::character varying NOT NULL,
    admin_sidebar_color character varying DEFAULT '#FFFFFF'::character varying NOT NULL,
    admin_workspace_color character varying DEFAULT '#EEF2F7'::character varying NOT NULL,
    interest_intelligence_enabled boolean DEFAULT true NOT NULL,
    interest_intelligence_instructions text,
    interest_intelligence_settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    admin_menu_section_colors jsonb DEFAULT '{"product": {"text_color": "#2563EB", "border_color": "#2563EB", "background_color": "#2563EB", "background_opacity": 30}, "operation": {"text_color": "#0F766E", "border_color": "#0F766E", "background_color": "#0F766E", "background_opacity": 30}, "management": {"text_color": "#7C3AED", "border_color": "#7C3AED", "background_color": "#7C3AED", "background_opacity": 30}, "growth": {"text_color": "#DB2777", "border_color": "#DB2777", "background_color": "#DB2777", "background_opacity": 30}, "public_site": {"text_color": "#0891B2", "border_color": "#0891B2", "background_color": "#0891B2", "background_opacity": 30}, "integrations": {"text_color": "#D97706", "border_color": "#D97706", "background_color": "#D97706", "background_opacity": 30}, "settings": {"text_color": "#64748B", "border_color": "#64748B", "background_color": "#64748B", "background_opacity": 30}, "account": {"text_color": "#475569", "border_color": "#475569", "background_color": "#475569", "background_opacity": 30}}'::jsonb NOT NULL
);


--
-- Name: layout_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.layout_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: layout_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.layout_settings_id_seq OWNED BY public.layout_settings.id;


--
-- Name: lead_activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lead_activities (
    id bigint NOT NULL,
    lead_id bigint NOT NULL,
    kind character varying,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: lead_activities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.lead_activities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lead_activities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.lead_activities_id_seq OWNED BY public.lead_activities.id;


--
-- Name: lead_audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lead_audit_logs (
    id bigint NOT NULL,
    lead_id bigint NOT NULL,
    admin_user_id bigint,
    action character varying NOT NULL,
    source character varying NOT NULL,
    changed_fields text[] DEFAULT '{}'::text[] NOT NULL,
    changeset jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    ip inet,
    user_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: lead_audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.lead_audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lead_audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.lead_audit_logs_id_seq OWNED BY public.lead_audit_logs.id;


--
-- Name: lead_labelings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lead_labelings (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    lead_id bigint NOT NULL,
    lead_label_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: lead_labelings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.lead_labelings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lead_labelings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.lead_labelings_id_seq OWNED BY public.lead_labelings.id;


--
-- Name: lead_labels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lead_labels (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    admin_user_id bigint NOT NULL,
    name character varying NOT NULL,
    color character varying DEFAULT 'gray'::character varying NOT NULL,
    "position" integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: lead_labels_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.lead_labels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lead_labels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.lead_labels_id_seq OWNED BY public.lead_labels.id;


--
-- Name: lead_property_interests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lead_property_interests (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    lead_id bigint NOT NULL,
    habitation_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: lead_property_interests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.lead_property_interests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lead_property_interests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.lead_property_interests_id_seq OWNED BY public.lead_property_interests.id;


--
-- Name: lead_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lead_settings (
    id bigint NOT NULL,
    stickiness_enabled boolean DEFAULT false NOT NULL,
    stickiness_match character varying DEFAULT 'phone'::character varying NOT NULL,
    stickiness_owner character varying DEFAULT 'attended'::character varying NOT NULL,
    stickiness_fallback character varying DEFAULT 'active_in_rule'::character varying NOT NULL,
    stickiness_window_days integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    secure_links_enabled boolean DEFAULT false NOT NULL,
    secure_link_expiry_days integer DEFAULT 7 NOT NULL,
    notify_on_direct_assignment boolean DEFAULT true NOT NULL,
    notify_on_reassignment boolean DEFAULT true NOT NULL,
    notify_on_lost_turn boolean DEFAULT false NOT NULL,
    notify_on_shark_tank boolean DEFAULT true NOT NULL,
    notify_on_distribution boolean DEFAULT true NOT NULL,
    notify_on_sticky boolean DEFAULT true NOT NULL,
    notify_on_redistribution boolean DEFAULT true NOT NULL,
    secure_link_whatsapp boolean DEFAULT true NOT NULL,
    secure_link_email boolean DEFAULT true NOT NULL,
    secure_link_push boolean DEFAULT true NOT NULL
);


--
-- Name: lead_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.lead_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lead_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.lead_settings_id_seq OWNED BY public.lead_settings.id;


--
-- Name: leads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leads (
    id bigint NOT NULL,
    name character varying,
    email character varying,
    phone character varying,
    property_id integer,
    source_url character varying,
    lead_type character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    status character varying,
    notes text,
    client_name character varying,
    client_email character varying,
    client_phone character varying,
    client_c2s_id character varying,
    agent_name character varying,
    agent_email character varying,
    agent_phone character varying,
    agent_c2s_id character varying,
    event_name character varying,
    origin character varying,
    product character varying,
    other_information jsonb DEFAULT '{}'::jsonb,
    custom_answers jsonb DEFAULT '[]'::jsonb,
    distribution_rule_id bigint,
    admin_user_id bigint,
    share_token character varying,
    shared_by_admin_user_id bigint,
    vista_import_batch_id bigint,
    vista_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    business_scoped_user_id character varying,
    tags jsonb DEFAULT '[]'::jsonb NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: leads_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.leads_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: leads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.leads_id_seq OWNED BY public.leads.id;


--
-- Name: location_pings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.location_pings (
    id bigint NOT NULL,
    check_in_id bigint NOT NULL,
    admin_user_id bigint NOT NULL,
    accuracy_meters integer,
    battery_level double precision,
    is_mock_location boolean DEFAULT false NOT NULL,
    inside_radius boolean NOT NULL,
    ip inet,
    user_agent character varying,
    recorded_at timestamp(6) without time zone NOT NULL,
    suspicious boolean DEFAULT false NOT NULL,
    suspicious_reasons jsonb DEFAULT '[]'::jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    location public.geography(Point,4326) NOT NULL
);


--
-- Name: location_pings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.location_pings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: location_pings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.location_pings_id_seq OWNED BY public.location_pings.id;


--
-- Name: manual_checkin_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.manual_checkin_requests (
    id bigint NOT NULL,
    admin_user_id bigint NOT NULL,
    store_id bigint NOT NULL,
    justification text NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    reviewed_by_admin_user_id bigint,
    reviewed_at timestamp(6) without time zone,
    review_notes text,
    approved_check_in_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: manual_checkin_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.manual_checkin_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: manual_checkin_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.manual_checkin_requests_id_seq OWNED BY public.manual_checkin_requests.id;


--
-- Name: marketing_campaigns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.marketing_campaigns (
    id bigint NOT NULL,
    seo_setting_id bigint,
    admin_user_id bigint,
    name character varying NOT NULL,
    channel character varying DEFAULT 'organic'::character varying NOT NULL,
    status character varying DEFAULT 'idea'::character varying NOT NULL,
    target_url character varying,
    objective character varying,
    budget_cents integer DEFAULT 0 NOT NULL,
    starts_on date,
    ends_on date,
    priority integer DEFAULT 3 NOT NULL,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    slug character varying,
    utm_source character varying,
    utm_medium character varying,
    utm_campaign character varying,
    utm_term character varying,
    utm_content character varying,
    clicks_count integer DEFAULT 0 NOT NULL,
    conversions_count integer DEFAULT 0 NOT NULL,
    last_clicked_at timestamp(6) without time zone
);


--
-- Name: marketing_campaigns_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.marketing_campaigns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: marketing_campaigns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.marketing_campaigns_id_seq OWNED BY public.marketing_campaigns.id;


--
-- Name: meta_facebook_pages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.meta_facebook_pages (
    id bigint NOT NULL,
    user_meta_integration_id bigint NOT NULL,
    page_id character varying,
    name character varying,
    access_token character varying,
    active boolean DEFAULT true,
    category character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: meta_facebook_pages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.meta_facebook_pages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: meta_facebook_pages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.meta_facebook_pages_id_seq OWNED BY public.meta_facebook_pages.id;


--
-- Name: meta_lead_forms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.meta_lead_forms (
    id bigint NOT NULL,
    meta_facebook_page_id bigint NOT NULL,
    form_id character varying,
    name character varying,
    active boolean DEFAULT true,
    facebook_created_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: meta_lead_forms_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.meta_lead_forms_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: meta_lead_forms_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.meta_lead_forms_id_seq OWNED BY public.meta_lead_forms.id;


--
-- Name: notification_template_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_template_settings (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    whatsapp_template_id bigint,
    channel character varying DEFAULT 'whatsapp'::character varying NOT NULL,
    purpose character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: notification_template_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notification_template_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notification_template_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notification_template_settings_id_seq OWNED BY public.notification_template_settings.id;


--
-- Name: photography_schedule_blocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.photography_schedule_blocks (
    id bigint NOT NULL,
    date date NOT NULL,
    reason character varying,
    created_by_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: photography_schedule_blocks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.photography_schedule_blocks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: photography_schedule_blocks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.photography_schedule_blocks_id_seq OWNED BY public.photography_schedule_blocks.id;


--
-- Name: portal_integration_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.portal_integration_events (
    id bigint NOT NULL,
    portal character varying NOT NULL,
    habitation_id bigint,
    habitation_code character varying,
    external_listing_id character varying,
    event_type character varying NOT NULL,
    normalized_status character varying,
    received_at timestamp(6) without time zone NOT NULL,
    source_ip character varying,
    raw_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint
);


--
-- Name: portal_integration_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.portal_integration_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: portal_integration_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.portal_integration_events_id_seq OWNED BY public.portal_integration_events.id;


--
-- Name: portal_integrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.portal_integrations (
    id bigint NOT NULL,
    portal character varying NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    allowed_statuses character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    allowed_business_types character varying[] DEFAULT '{venda,aluguel}'::character varying[] NOT NULL,
    require_exibir_no_site boolean DEFAULT true NOT NULL,
    feed_token character varying NOT NULL,
    account_id character varying,
    publisher_id character varying,
    webhook_secret character varying,
    operational_status character varying DEFAULT 'idle'::character varying NOT NULL,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    last_feed_at timestamp(6) without time zone,
    last_webhook_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint
);


--
-- Name: portal_integrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.portal_integrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: portal_integrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.portal_integrations_id_seq OWNED BY public.portal_integrations.id;


--
-- Name: portal_listing_states; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.portal_listing_states (
    id bigint NOT NULL,
    portal character varying NOT NULL,
    habitation_id bigint,
    habitation_code character varying,
    external_listing_id character varying,
    last_event_type character varying NOT NULL,
    last_status character varying,
    last_received_at timestamp(6) without time zone NOT NULL,
    last_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint
);


--
-- Name: portal_listing_states_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.portal_listing_states_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: portal_listing_states_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.portal_listing_states_id_seq OWNED BY public.portal_listing_states.id;


--
-- Name: presentation_cards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.presentation_cards (
    id bigint NOT NULL,
    tenant_id bigint NOT NULL,
    admin_user_id bigint,
    label character varying NOT NULL,
    greeting text NOT NULL,
    use_photo boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    system boolean DEFAULT false NOT NULL
);


--
-- Name: presentation_cards_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.presentation_cards_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: presentation_cards_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.presentation_cards_id_seq OWNED BY public.presentation_cards.id;


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id bigint NOT NULL,
    name character varying,
    permissions jsonb,
    active boolean,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    key character varying,
    tenant_id bigint NOT NULL,
    axis character varying DEFAULT 'vertical'::character varying NOT NULL,
    vertical_profile_id bigint,
    "position" integer,
    locked boolean DEFAULT false NOT NULL
);


--
-- Name: profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.profiles_id_seq OWNED BY public.profiles.id;


--
-- Name: property_pages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.property_pages (
    id bigint NOT NULL,
    title character varying NOT NULL,
    meta_title character varying,
    meta_description text,
    slug character varying NOT NULL,
    filter_params jsonb DEFAULT '{}'::jsonb,
    active boolean DEFAULT true,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: property_pages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.property_pages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: property_pages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.property_pages_id_seq OWNED BY public.property_pages.id;


--
-- Name: property_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.property_settings (
    id bigint NOT NULL,
    watermark_position character varying DEFAULT 'bottom_left'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    watermark_size_percentage integer DEFAULT 28 NOT NULL,
    watermark_opacity_percentage integer DEFAULT 100 NOT NULL,
    broker_capture_layer_enabled boolean DEFAULT true NOT NULL,
    required_broker_intake_checks text[] DEFAULT '{}'::text[] NOT NULL,
    returnable_intake_edit_sections text[] DEFAULT '{}'::text[] NOT NULL,
    broker_capture_fallback_admin_user_id bigint,
    notify_internal_review_events boolean DEFAULT true NOT NULL,
    notify_email_review_events boolean DEFAULT false NOT NULL,
    review_notification_emails text,
    tenant_id bigint
);


--
-- Name: property_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.property_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: property_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.property_settings_id_seq OWNED BY public.property_settings.id;


--
-- Name: proposals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proposals (
    id bigint NOT NULL,
    lead_id bigint NOT NULL,
    habitation_id bigint,
    admin_user_id bigint NOT NULL,
    public_token character varying NOT NULL,
    title character varying,
    valor_cents integer DEFAULT 0 NOT NULL,
    entrada_cents integer DEFAULT 0 NOT NULL,
    condicoes text,
    extra jsonb DEFAULT '{}'::jsonb NOT NULL,
    validade date,
    status character varying DEFAULT 'rascunho'::character varying NOT NULL,
    sent_at timestamp(6) without time zone,
    viewed_at timestamp(6) without time zone,
    responded_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: proposals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.proposals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proposals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.proposals_id_seq OWNED BY public.proposals.id;


--
-- Name: proprietors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.proprietors (
    id bigint NOT NULL,
    name character varying NOT NULL,
    role integer DEFAULT 0 NOT NULL,
    vista_code character varying,
    cpf_cnpj character varying,
    rg_ie character varying,
    issuing_authority character varying,
    birth_date date,
    email character varying,
    phone_primary character varying,
    mobile_phone character varying,
    residential_phone character varying,
    business_phone character varying,
    phone_extension character varying,
    profession character varying,
    marital_status character varying,
    marriage_regime character varying,
    nationality character varying,
    capture_vehicle character varying,
    registered_at date,
    notes text,
    is_client boolean DEFAULT false NOT NULL,
    address_type character varying,
    street character varying,
    number character varying,
    complement character varying,
    block character varying,
    uf character varying(2),
    cep character varying(10),
    neighborhood character varying,
    city character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    spouse_name character varying,
    spouse_email character varying,
    spouse_phone character varying,
    spouse_cpf_cnpj character varying,
    vista_import_batch_id bigint,
    vista_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    source_status character varying,
    source_updated_at timestamp(6) without time zone,
    potential_value_cents bigint,
    favorite boolean DEFAULT false NOT NULL,
    restricted boolean DEFAULT false NOT NULL,
    receive_information boolean DEFAULT false NOT NULL,
    show_email_to_client boolean DEFAULT false NOT NULL,
    show_phone_on_web boolean DEFAULT false NOT NULL,
    spouse_birth_date date,
    tenant_id bigint NOT NULL,
    cpf_cnpj_digits character varying,
    spouse_cpf_cnpj_digits character varying
);


--
-- Name: proprietors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.proprietors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: proprietors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.proprietors_id_seq OWNED BY public.proprietors.id;


--
-- Name: public_navigation_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.public_navigation_events (
    id bigint NOT NULL,
    public_navigation_session_id bigint NOT NULL,
    lead_id bigint,
    habitation_id bigint,
    name character varying NOT NULL,
    path character varying,
    duration_seconds integer,
    occurred_at timestamp(6) without time zone NOT NULL,
    search_params jsonb DEFAULT '{}'::jsonb NOT NULL,
    property_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: public_navigation_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.public_navigation_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: public_navigation_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.public_navigation_events_id_seq OWNED BY public.public_navigation_events.id;


--
-- Name: public_navigation_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.public_navigation_sessions (
    id bigint NOT NULL,
    token character varying NOT NULL,
    lead_id bigint,
    user_agent_digest character varying,
    landing_url character varying,
    referrer_url character varying,
    first_seen_at timestamp(6) without time zone NOT NULL,
    last_seen_at timestamp(6) without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: public_navigation_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.public_navigation_sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: public_navigation_sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.public_navigation_sessions_id_seq OWNED BY public.public_navigation_sessions.id;


--
-- Name: push_delivery_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.push_delivery_events (
    id bigint NOT NULL,
    admin_user_id bigint NOT NULL,
    push_subscription_id bigint,
    lead_id bigint,
    event_type character varying NOT NULL,
    tag character varying,
    endpoint_host character varying,
    endpoint_sha256 character varying,
    user_agent text,
    provider_status character varying,
    error_class character varying,
    error_message text,
    urgency character varying,
    ttl integer,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: push_delivery_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.push_delivery_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: push_delivery_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.push_delivery_events_id_seq OWNED BY public.push_delivery_events.id;


--
-- Name: push_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.push_settings (
    id bigint NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    vapid_public_key text,
    vapid_private_key text,
    subject_email character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    lead_click_action character varying DEFAULT 'whatsapp'::character varying NOT NULL
);


--
-- Name: push_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.push_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: push_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.push_settings_id_seq OWNED BY public.push_settings.id;


--
-- Name: push_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.push_subscriptions (
    id bigint NOT NULL,
    admin_user_id bigint NOT NULL,
    endpoint character varying NOT NULL,
    p256dh character varying NOT NULL,
    auth character varying NOT NULL,
    platform character varying,
    user_agent character varying,
    last_seen_at timestamp(6) without time zone,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: push_subscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.push_subscriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: push_subscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.push_subscriptions_id_seq OWNED BY public.push_subscriptions.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: secure_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.secure_links (
    id bigint NOT NULL,
    lead_id bigint NOT NULL,
    token character varying NOT NULL,
    action_type integer DEFAULT 0 NOT NULL,
    expires_at timestamp(6) without time zone,
    active boolean DEFAULT true NOT NULL,
    access_count integer DEFAULT 0 NOT NULL,
    first_accessed_at timestamp(6) without time zone,
    last_accessed_at timestamp(6) without time zone,
    issued_to_admin_user_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: secure_links_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.secure_links_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: secure_links_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.secure_links_id_seq OWNED BY public.secure_links.id;


--
-- Name: seo_change_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.seo_change_logs (
    id bigint NOT NULL,
    seo_setting_id bigint NOT NULL,
    admin_user_id bigint,
    event_type character varying DEFAULT 'update'::character varying NOT NULL,
    changed_fields jsonb DEFAULT '{}'::jsonb NOT NULL,
    snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: seo_change_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.seo_change_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: seo_change_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.seo_change_logs_id_seq OWNED BY public.seo_change_logs.id;


--
-- Name: seo_conversion_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.seo_conversion_events (
    id bigint NOT NULL,
    seo_setting_id bigint,
    marketing_campaign_id bigint,
    lead_id bigint,
    habitation_id bigint,
    event_type character varying NOT NULL,
    visitor_hash character varying,
    path character varying,
    source_path character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    occurred_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: seo_conversion_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.seo_conversion_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: seo_conversion_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.seo_conversion_events_id_seq OWNED BY public.seo_conversion_events.id;


--
-- Name: seo_focus_keywords; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.seo_focus_keywords (
    id bigint NOT NULL,
    seo_setting_id bigint NOT NULL,
    keyword character varying NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: seo_focus_keywords_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.seo_focus_keywords_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: seo_focus_keywords_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.seo_focus_keywords_id_seq OWNED BY public.seo_focus_keywords.id;


--
-- Name: seo_page_visits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.seo_page_visits (
    id bigint NOT NULL,
    seo_setting_id bigint NOT NULL,
    visitor_hash character varying NOT NULL,
    session_hash character varying,
    user_agent_hash character varying,
    path character varying NOT NULL,
    visited_on date NOT NULL,
    visits_count integer DEFAULT 1 NOT NULL,
    first_seen_at timestamp(6) without time zone NOT NULL,
    last_seen_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: seo_page_visits_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.seo_page_visits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: seo_page_visits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.seo_page_visits_id_seq OWNED BY public.seo_page_visits.id;


--
-- Name: seo_redirects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.seo_redirects (
    id bigint NOT NULL,
    from_path character varying NOT NULL,
    to_path character varying NOT NULL,
    status_code integer DEFAULT 301 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    hit_count integer DEFAULT 0 NOT NULL,
    last_hit_at timestamp(6) without time zone,
    created_by_admin_user_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: seo_redirects_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.seo_redirects_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: seo_redirects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.seo_redirects_id_seq OWNED BY public.seo_redirects.id;


--
-- Name: seo_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.seo_settings (
    id bigint NOT NULL,
    page_name character varying,
    meta_title character varying,
    meta_description text,
    meta_keywords text,
    og_image character varying,
    canonical_url character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    canonical_key character varying NOT NULL,
    page_type character varying,
    controller_name character varying,
    action_name character varying,
    canonical_path character varying,
    normalized_params jsonb DEFAULT '{}'::jsonb NOT NULL,
    og_title character varying,
    og_description text,
    robots_index boolean DEFAULT true NOT NULL,
    robots_follow boolean DEFAULT true NOT NULL,
    active boolean DEFAULT true NOT NULL,
    apply_to_public boolean DEFAULT true NOT NULL,
    manual_mode boolean DEFAULT false NOT NULL,
    auto_discovered boolean DEFAULT false NOT NULL,
    ai_status character varying DEFAULT 'pending'::character varying NOT NULL,
    ai_generated_at timestamp(6) without time zone,
    ai_error_message text,
    ai_insights text,
    seo_score integer DEFAULT 0 NOT NULL,
    access_count integer DEFAULT 0 NOT NULL,
    last_accessed_at timestamp(6) without time zone,
    last_generated_from_path character varying,
    intro_text text
);


--
-- Name: seo_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.seo_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: seo_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.seo_settings_id_seq OWNED BY public.seo_settings.id;


--
-- Name: settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.settings (
    id bigint NOT NULL,
    key character varying,
    value text,
    description character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint
);


--
-- Name: settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.settings_id_seq OWNED BY public.settings.id;


--
-- Name: solid_queue_blocked_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_blocked_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    concurrency_key character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_blocked_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_blocked_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_blocked_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_blocked_executions_id_seq OWNED BY public.solid_queue_blocked_executions.id;


--
-- Name: solid_queue_claimed_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_claimed_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    process_id bigint,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_claimed_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_claimed_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_claimed_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_claimed_executions_id_seq OWNED BY public.solid_queue_claimed_executions.id;


--
-- Name: solid_queue_failed_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_failed_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    error text,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_failed_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_failed_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_failed_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_failed_executions_id_seq OWNED BY public.solid_queue_failed_executions.id;


--
-- Name: solid_queue_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_jobs (
    id bigint NOT NULL,
    queue_name character varying NOT NULL,
    class_name character varying NOT NULL,
    arguments text,
    priority integer DEFAULT 0 NOT NULL,
    active_job_id character varying,
    scheduled_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    concurrency_key character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_jobs_id_seq OWNED BY public.solid_queue_jobs.id;


--
-- Name: solid_queue_pauses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_pauses (
    id bigint NOT NULL,
    queue_name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_pauses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_pauses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_pauses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_pauses_id_seq OWNED BY public.solid_queue_pauses.id;


--
-- Name: solid_queue_processes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_processes (
    id bigint NOT NULL,
    kind character varying NOT NULL,
    last_heartbeat_at timestamp(6) without time zone NOT NULL,
    supervisor_id bigint,
    pid integer NOT NULL,
    hostname character varying,
    metadata text,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL
);


--
-- Name: solid_queue_processes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_processes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_processes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_processes_id_seq OWNED BY public.solid_queue_processes.id;


--
-- Name: solid_queue_ready_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_ready_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_ready_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_ready_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_ready_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_ready_executions_id_seq OWNED BY public.solid_queue_ready_executions.id;


--
-- Name: solid_queue_recurring_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_recurring_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    task_key character varying NOT NULL,
    run_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_recurring_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_recurring_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_recurring_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_recurring_executions_id_seq OWNED BY public.solid_queue_recurring_executions.id;


--
-- Name: solid_queue_recurring_tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_recurring_tasks (
    id bigint NOT NULL,
    key character varying NOT NULL,
    schedule character varying NOT NULL,
    command character varying(2048),
    class_name character varying,
    arguments text,
    queue_name character varying,
    priority integer DEFAULT 0,
    static boolean DEFAULT true NOT NULL,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_recurring_tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_recurring_tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_recurring_tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_recurring_tasks_id_seq OWNED BY public.solid_queue_recurring_tasks.id;


--
-- Name: solid_queue_scheduled_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_scheduled_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    scheduled_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_scheduled_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_scheduled_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_scheduled_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_scheduled_executions_id_seq OWNED BY public.solid_queue_scheduled_executions.id;


--
-- Name: solid_queue_semaphores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_semaphores (
    id bigint NOT NULL,
    key character varying NOT NULL,
    value integer DEFAULT 1 NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_semaphores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_semaphores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_semaphores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_semaphores_id_seq OWNED BY public.solid_queue_semaphores.id;


--
-- Name: storage_integration_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.storage_integration_settings (
    id bigint NOT NULL,
    photo_provider character varying DEFAULT 'local'::character varying NOT NULL,
    document_provider character varying DEFAULT 'local'::character varying NOT NULL,
    public_photos_enabled boolean DEFAULT true NOT NULL,
    do_spaces_bucket character varying,
    do_spaces_region character varying DEFAULT 'sfo3'::character varying NOT NULL,
    do_spaces_endpoint character varying DEFAULT 'https://sfo3.digitaloceanspaces.com'::character varying NOT NULL,
    do_spaces_public_base_url character varying,
    do_spaces_access_key_id_ciphertext text,
    do_spaces_secret_access_key_ciphertext text,
    s3_bucket character varying,
    s3_region character varying DEFAULT 'us-east-1'::character varying NOT NULL,
    s3_endpoint character varying,
    s3_public_base_url character varying,
    s3_access_key_id_ciphertext text,
    s3_secret_access_key_ciphertext text,
    last_tested_at timestamp(6) without time zone,
    last_test_status character varying,
    last_test_message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: storage_integration_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.storage_integration_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: storage_integration_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.storage_integration_settings_id_seq OWNED BY public.storage_integration_settings.id;


--
-- Name: store_shifts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.store_shifts (
    id bigint NOT NULL,
    store_id bigint NOT NULL,
    admin_user_id bigint NOT NULL,
    day_of_week integer NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: store_shifts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.store_shifts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: store_shifts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.store_shifts_id_seq OWNED BY public.store_shifts.id;


--
-- Name: stores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stores (
    id bigint NOT NULL,
    name character varying NOT NULL,
    slug character varying,
    address character varying,
    zip_code character varying,
    city character varying,
    state character varying(2),
    phone character varying,
    creci character varying,
    geofence_radius_meters integer DEFAULT 150 NOT NULL,
    out_of_radius_tolerance_minutes integer DEFAULT 10 NOT NULL,
    auto_checkout_after_minutes integer DEFAULT 60 NOT NULL,
    timezone character varying DEFAULT 'America/Sao_Paulo'::character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    director_admin_user_id bigint,
    footer_store_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    location public.geography(Point,4326),
    number character varying,
    neighborhood character varying,
    tenant_id bigint NOT NULL,
    turnos_config jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: stores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stores_id_seq OWNED BY public.stores.id;


--
-- Name: system_notification_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_notification_settings (
    id bigint NOT NULL,
    whatsapp_enabled boolean DEFAULT false NOT NULL,
    whatsapp_access_token text,
    whatsapp_phone_number_id character varying,
    whatsapp_business_account_id character varying,
    whatsapp_template_name character varying,
    facebook_app_secret text,
    whatsapp_app_secret text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: system_notification_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.system_notification_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: system_notification_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.system_notification_settings_id_seq OWNED BY public.system_notification_settings.id;


--
-- Name: tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasks (
    id bigint NOT NULL,
    lead_id bigint,
    admin_user_id bigint NOT NULL,
    created_by_id bigint,
    title character varying NOT NULL,
    description text,
    kind character varying DEFAULT 'follow_up'::character varying NOT NULL,
    due_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    status character varying DEFAULT 'pendente'::character varying NOT NULL,
    priority character varying DEFAULT 'normal'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tasks_id_seq OWNED BY public.tasks.id;


--
-- Name: tenants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenants (
    id bigint NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    require_two_factor boolean DEFAULT false NOT NULL,
    enforce_broker_ip_allowlist boolean DEFAULT false NOT NULL,
    enforce_broker_trusted_devices boolean DEFAULT false NOT NULL,
    session_timeout_enabled boolean DEFAULT false NOT NULL,
    session_timeout_days integer DEFAULT 7,
    session_remember_days integer,
    session_epoch_at timestamp(6) without time zone,
    use_global_whatsapp_fallback boolean DEFAULT false NOT NULL,
    use_global_email_fallback boolean DEFAULT false NOT NULL
);


--
-- Name: tenants_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tenants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tenants_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tenants_id_seq OWNED BY public.tenants.id;


--
-- Name: trusted_devices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trusted_devices (
    id bigint NOT NULL,
    admin_user_id bigint NOT NULL,
    created_by_id bigint,
    name character varying,
    fingerprint character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    device_type character varying,
    browser character varying,
    platform character varying,
    last_ip inet,
    user_agent character varying,
    trusted_at timestamp(6) without time zone,
    last_seen_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint
);


--
-- Name: trusted_devices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trusted_devices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trusted_devices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trusted_devices_id_seq OWNED BY public.trusted_devices.id;


--
-- Name: user_meta_integrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_meta_integrations (
    id bigint NOT NULL,
    admin_user_id bigint NOT NULL,
    access_token character varying,
    facebook_user_id character varying,
    name character varying,
    email character varying,
    token_expires_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    sync_status character varying,
    sync_progress integer,
    last_synced_at timestamp(6) without time zone,
    sync_message character varying,
    tenant_id bigint
);


--
-- Name: user_meta_integrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_meta_integrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_meta_integrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_meta_integrations_id_seq OWNED BY public.user_meta_integrations.id;


--
-- Name: vista_file_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vista_file_assets (
    id bigint NOT NULL,
    vista_import_batch_id bigint NOT NULL,
    vista_raw_record_id bigint,
    habitation_id bigint,
    table_name character varying NOT NULL,
    kind character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    codigo_imovel character varying,
    codigo_cliente character varying,
    codigo_corretor character varying,
    source_path character varying NOT NULL,
    source_url character varying,
    filename character varying NOT NULL,
    active_storage_name character varying,
    active_storage_attachment_id bigint,
    "position" integer,
    attempts integer DEFAULT 0 NOT NULL,
    downloaded_at timestamp(6) without time zone,
    error_message text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    active_storage_key character varying,
    storage_checksum character varying,
    storage_byte_size bigint,
    storage_content_type character varying,
    storage_service_name character varying,
    reused_at timestamp(6) without time zone
);


--
-- Name: vista_file_assets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.vista_file_assets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: vista_file_assets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.vista_file_assets_id_seq OWNED BY public.vista_file_assets.id;


--
-- Name: vista_import_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vista_import_batches (
    id bigint NOT NULL,
    dump_dir character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    started_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    error_message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: vista_import_batches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.vista_import_batches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: vista_import_batches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.vista_import_batches_id_seq OWNED BY public.vista_import_batches.id;


--
-- Name: vista_raw_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vista_raw_records (
    id bigint NOT NULL,
    vista_import_batch_id bigint NOT NULL,
    table_name character varying NOT NULL,
    row_index integer NOT NULL,
    source_key character varying,
    codigo_imovel character varying,
    codigo_cliente character varying,
    codigo_corretor character varying,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: vista_raw_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.vista_raw_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: vista_raw_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.vista_raw_records_id_seq OWNED BY public.vista_raw_records.id;


--
-- Name: webhook_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_settings (
    id bigint NOT NULL,
    webhook_url character varying,
    enabled boolean DEFAULT true NOT NULL,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    whatsapp_webhook_url character varying,
    lead_capture_enabled boolean
);


--
-- Name: webhook_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.webhook_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: webhook_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.webhook_settings_id_seq OWNED BY public.webhook_settings.id;


--
-- Name: whatsapp_business_integrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_business_integrations (
    id bigint NOT NULL,
    connected_by_admin_user_id bigint,
    waba_id character varying,
    phone_number_id character varying,
    business_id character varying,
    access_token text,
    status character varying DEFAULT 'disconnected'::character varying NOT NULL,
    last_event character varying,
    last_error_code character varying,
    last_error_message character varying,
    meta_session_id character varying,
    connected_at timestamp(6) without time zone,
    token_expires_at timestamp(6) without time zone,
    signup_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    default_whatsapp_number character varying,
    sale_whatsapp_number character varying,
    rent_whatsapp_number character varying,
    sale_rent_whatsapp_number character varying,
    sale_requires_lead_form boolean DEFAULT true NOT NULL,
    rent_requires_lead_form boolean DEFAULT true NOT NULL,
    sale_rent_requires_lead_form boolean DEFAULT true NOT NULL,
    webhook_verify_token character varying,
    app_secret character varying,
    webhook_callback_url character varying,
    tenant_id bigint NOT NULL,
    allow_photo_presentation boolean DEFAULT false NOT NULL,
    presentation_enabled boolean DEFAULT true NOT NULL,
    require_presentation boolean DEFAULT false NOT NULL,
    require_presentation_since timestamp(6) without time zone,
    inbox_attendance_enabled boolean DEFAULT false NOT NULL
);


--
-- Name: whatsapp_business_integrations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.whatsapp_business_integrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: whatsapp_business_integrations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.whatsapp_business_integrations_id_seq OWNED BY public.whatsapp_business_integrations.id;


--
-- Name: whatsapp_campaign_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_campaign_messages (
    id bigint NOT NULL,
    whatsapp_campaign_id bigint NOT NULL,
    lead_id bigint,
    whatsapp_message_id bigint,
    phone_number character varying NOT NULL,
    external_message_id character varying,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    template_variables jsonb DEFAULT '{}'::jsonb NOT NULL,
    queued_at timestamp(6) without time zone,
    sent_at timestamp(6) without time zone,
    delivered_at timestamp(6) without time zone,
    read_at timestamp(6) without time zone,
    failed_at timestamp(6) without time zone,
    replied_at timestamp(6) without time zone,
    failure_reason text,
    retry_count integer DEFAULT 0 NOT NULL,
    next_retry_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    whatsapp_campaign_recipient_id bigint,
    reply_type character varying,
    reply_body text,
    reply_button_text character varying,
    reply_button_payload character varying,
    reply_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: whatsapp_campaign_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.whatsapp_campaign_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: whatsapp_campaign_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.whatsapp_campaign_messages_id_seq OWNED BY public.whatsapp_campaign_messages.id;


--
-- Name: whatsapp_campaign_recipients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_campaign_recipients (
    id bigint NOT NULL,
    whatsapp_campaign_id bigint NOT NULL,
    lead_id bigint,
    admin_user_id bigint,
    source character varying DEFAULT 'spreadsheet'::character varying NOT NULL,
    name character varying,
    phone_number character varying NOT NULL,
    email character varying,
    origin character varying,
    status character varying,
    tags jsonb DEFAULT '[]'::jsonb NOT NULL,
    custom_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    conversion_status character varying DEFAULT 'pending'::character varying NOT NULL,
    converted_at timestamp(6) without time zone,
    unsubscribed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: whatsapp_campaign_recipients_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.whatsapp_campaign_recipients_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: whatsapp_campaign_recipients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.whatsapp_campaign_recipients_id_seq OWNED BY public.whatsapp_campaign_recipients.id;


--
-- Name: whatsapp_campaign_unsubscribes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_campaign_unsubscribes (
    id bigint NOT NULL,
    whatsapp_sender_number_id bigint NOT NULL,
    whatsapp_campaign_id bigint,
    whatsapp_campaign_message_id bigint,
    whatsapp_campaign_recipient_id bigint,
    unsubscribed_by_message_id bigint,
    reenabled_by_id bigint,
    phone_number character varying NOT NULL,
    contact_name character varying,
    source character varying DEFAULT 'campaign_button'::character varying NOT NULL,
    reason character varying DEFAULT 'Descadastro solicitado pelo contato.'::character varying NOT NULL,
    unsubscribed_at timestamp(6) without time zone NOT NULL,
    reenabled_at timestamp(6) without time zone,
    reenable_reason text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tenant_id bigint NOT NULL
);


--
-- Name: whatsapp_campaign_unsubscribes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.whatsapp_campaign_unsubscribes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: whatsapp_campaign_unsubscribes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.whatsapp_campaign_unsubscribes_id_seq OWNED BY public.whatsapp_campaign_unsubscribes.id;


--
-- Name: whatsapp_campaigns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_campaigns (
    id bigint NOT NULL,
    whatsapp_template_id bigint NOT NULL,
    created_by_id bigint NOT NULL,
    name character varying NOT NULL,
    description text,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    audience_filters jsonb DEFAULT '{}'::jsonb NOT NULL,
    template_variables jsonb DEFAULT '{}'::jsonb NOT NULL,
    scheduled_at timestamp(6) without time zone,
    started_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    paused_at timestamp(6) without time zone,
    cancelled_at timestamp(6) without time zone,
    send_rate integer DEFAULT 50 NOT NULL,
    requested_recipients integer DEFAULT 0 NOT NULL,
    total_recipients integer DEFAULT 0 NOT NULL,
    sent_count integer DEFAULT 0 NOT NULL,
    delivered_count integer DEFAULT 0 NOT NULL,
    read_count integer DEFAULT 0 NOT NULL,
    failed_count integer DEFAULT 0 NOT NULL,
    replied_count integer DEFAULT 0 NOT NULL,
    failure_reason text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    whatsapp_sender_number_id bigint,
    group_name character varying,
    audience_mode character varying DEFAULT 'filters'::character varying NOT NULL,
    audience_definition jsonb DEFAULT '{}'::jsonb NOT NULL,
    import_batch_size integer DEFAULT 300 NOT NULL,
    import_interval_minutes integer DEFAULT 1 NOT NULL,
    import_status character varying,
    import_total_rows integer DEFAULT 0 NOT NULL,
    import_valid_rows integer DEFAULT 0 NOT NULL,
    import_invalid_rows integer DEFAULT 0 NOT NULL,
    import_last_error text,
    response_decisions jsonb DEFAULT '{}'::jsonb NOT NULL,
    automation_workflow_id bigint,
    tenant_id bigint NOT NULL
);


--
-- Name: whatsapp_campaigns_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.whatsapp_campaigns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: whatsapp_campaigns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.whatsapp_campaigns_id_seq OWNED BY public.whatsapp_campaigns.id;


--
-- Name: whatsapp_conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_conversations (
    id bigint NOT NULL,
    lead_id bigint,
    assigned_admin_user_id bigint,
    contact_phone character varying,
    contact_name character varying,
    last_message_at timestamp(6) without time zone,
    last_message_preview character varying,
    unread_count integer DEFAULT 0 NOT NULL,
    status character varying DEFAULT 'open'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    business_scoped_user_id character varying,
    tenant_id bigint NOT NULL
);


--
-- Name: whatsapp_conversations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.whatsapp_conversations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: whatsapp_conversations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.whatsapp_conversations_id_seq OWNED BY public.whatsapp_conversations.id;


--
-- Name: whatsapp_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_messages (
    id bigint NOT NULL,
    whatsapp_conversation_id bigint NOT NULL,
    admin_user_id bigint,
    direction character varying NOT NULL,
    wa_message_id character varying,
    msg_type character varying DEFAULT 'text'::character varying NOT NULL,
    body text,
    media_url character varying,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    error_message character varying,
    template_name character varying,
    sent_at timestamp(6) without time zone,
    delivered_at timestamp(6) without time zone,
    read_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    recipient_user_id character varying,
    tenant_id bigint NOT NULL,
    presentation_card_id bigint,
    context_wa_message_id character varying,
    client_reaction character varying,
    agent_reaction character varying,
    pinned_at timestamp(6) without time zone,
    starred_at timestamp(6) without time zone,
    hidden_at timestamp(6) without time zone
);


--
-- Name: whatsapp_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.whatsapp_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: whatsapp_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.whatsapp_messages_id_seq OWNED BY public.whatsapp_messages.id;


--
-- Name: whatsapp_sender_numbers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_sender_numbers (
    id bigint NOT NULL,
    whatsapp_business_integration_id bigint,
    label character varying NOT NULL,
    display_phone_number character varying NOT NULL,
    phone_number_id character varying NOT NULL,
    waba_id character varying,
    verified_name character varying,
    quality_rating character varying,
    status character varying DEFAULT 'connected'::character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    cpl_sent_unit_price numeric(10,2) DEFAULT 0.59 NOT NULL,
    cpl_fla_unit_price numeric(10,2) DEFAULT 0.12 NOT NULL,
    tenant_id bigint NOT NULL,
    use_for_campaigns boolean DEFAULT true NOT NULL,
    use_for_notifications boolean DEFAULT false NOT NULL
);


--
-- Name: whatsapp_sender_numbers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.whatsapp_sender_numbers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: whatsapp_sender_numbers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.whatsapp_sender_numbers_id_seq OWNED BY public.whatsapp_sender_numbers.id;


--
-- Name: whatsapp_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.whatsapp_templates (
    id bigint NOT NULL,
    name character varying NOT NULL,
    language character varying DEFAULT 'pt_BR'::character varying NOT NULL,
    category character varying,
    body text,
    variables jsonb DEFAULT '[]'::jsonb NOT NULL,
    status character varying,
    meta_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    template_type character varying DEFAULT 'text'::character varying NOT NULL,
    allow_category_change boolean DEFAULT false NOT NULL,
    header_format character varying DEFAULT 'none'::character varying NOT NULL,
    header_text character varying,
    header_media_handle character varying,
    footer_text character varying,
    buttons jsonb DEFAULT '[]'::jsonb NOT NULL,
    example_values jsonb DEFAULT '[]'::jsonb NOT NULL,
    components jsonb DEFAULT '[]'::jsonb NOT NULL,
    submission_error text,
    carousel_cards jsonb DEFAULT '[]'::jsonb NOT NULL,
    flow_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    tenant_id bigint NOT NULL,
    waba_id character varying
);


--
-- Name: whatsapp_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.whatsapp_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: whatsapp_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.whatsapp_templates_id_seq OWNED BY public.whatsapp_templates.id;


--
-- Name: access_audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_audit_logs ALTER COLUMN id SET DEFAULT nextval('public.access_audit_logs_id_seq'::regclass);


--
-- Name: access_control_rules id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_control_rules ALTER COLUMN id SET DEFAULT nextval('public.access_control_rules_id_seq'::regclass);


--
-- Name: account_memberships id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_memberships ALTER COLUMN id SET DEFAULT nextval('public.account_memberships_id_seq'::regclass);


--
-- Name: action_text_rich_texts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.action_text_rich_texts ALTER COLUMN id SET DEFAULT nextval('public.action_text_rich_texts_id_seq'::regclass);


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: addresses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.addresses ALTER COLUMN id SET DEFAULT nextval('public.addresses_id_seq'::regclass);


--
-- Name: admin_users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users ALTER COLUMN id SET DEFAULT nextval('public.admin_users_id_seq'::regclass);


--
-- Name: ai_property_suggestions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_property_suggestions ALTER COLUMN id SET DEFAULT nextval('public.ai_property_suggestions_id_seq'::regclass);


--
-- Name: appointments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments ALTER COLUMN id SET DEFAULT nextval('public.appointments_id_seq'::regclass);


--
-- Name: attribute_options id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attribute_options ALTER COLUMN id SET DEFAULT nextval('public.attribute_options_id_seq'::regclass);


--
-- Name: automation_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_events ALTER COLUMN id SET DEFAULT nextval('public.automation_events_id_seq'::regclass);


--
-- Name: automation_execution_steps id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_execution_steps ALTER COLUMN id SET DEFAULT nextval('public.automation_execution_steps_id_seq'::regclass);


--
-- Name: automation_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_executions ALTER COLUMN id SET DEFAULT nextval('public.automation_executions_id_seq'::regclass);


--
-- Name: automation_rules id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_rules ALTER COLUMN id SET DEFAULT nextval('public.automation_rules_id_seq'::regclass);


--
-- Name: automation_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_runs ALTER COLUMN id SET DEFAULT nextval('public.automation_runs_id_seq'::regclass);


--
-- Name: automation_webhook_deliveries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_webhook_deliveries ALTER COLUMN id SET DEFAULT nextval('public.automation_webhook_deliveries_id_seq'::regclass);


--
-- Name: automation_workflow_versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_workflow_versions ALTER COLUMN id SET DEFAULT nextval('public.automation_workflow_versions_id_seq'::regclass);


--
-- Name: automation_workflows id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_workflows ALTER COLUMN id SET DEFAULT nextval('public.automation_workflows_id_seq'::regclass);


--
-- Name: banners id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banners ALTER COLUMN id SET DEFAULT nextval('public.banners_id_seq'::regclass);


--
-- Name: captacao_goals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.captacao_goals ALTER COLUMN id SET DEFAULT nextval('public.captacao_goals_id_seq'::regclass);


--
-- Name: captacoes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.captacoes ALTER COLUMN id SET DEFAULT nextval('public.captacoes_id_seq'::regclass);


--
-- Name: check_ins id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_ins ALTER COLUMN id SET DEFAULT nextval('public.check_ins_id_seq'::regclass);


--
-- Name: checkin_audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checkin_audit_logs ALTER COLUMN id SET DEFAULT nextval('public.checkin_audit_logs_id_seq'::regclass);


--
-- Name: client_interactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_interactions ALTER COLUMN id SET DEFAULT nextval('public.client_interactions_id_seq'::regclass);


--
-- Name: client_property_interests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_property_interests ALTER COLUMN id SET DEFAULT nextval('public.client_property_interests_id_seq'::regclass);


--
-- Name: constructors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.constructors ALTER COLUMN id SET DEFAULT nextval('public.constructors_id_seq'::regclass);


--
-- Name: contact_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_settings ALTER COLUMN id SET DEFAULT nextval('public.contact_settings_id_seq'::regclass);


--
-- Name: crm_appointments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_appointments ALTER COLUMN id SET DEFAULT nextval('public.crm_appointments_id_seq'::regclass);


--
-- Name: crm_contacts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_contacts ALTER COLUMN id SET DEFAULT nextval('public.crm_contacts_id_seq'::regclass);


--
-- Name: data_export_audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_export_audit_logs ALTER COLUMN id SET DEFAULT nextval('public.data_export_audit_logs_id_seq'::regclass);


--
-- Name: distribution_rule_agents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.distribution_rule_agents ALTER COLUMN id SET DEFAULT nextval('public.distribution_rule_agents_id_seq'::regclass);


--
-- Name: distribution_rules id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.distribution_rules ALTER COLUMN id SET DEFAULT nextval('public.distribution_rules_id_seq'::regclass);


--
-- Name: email_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_settings ALTER COLUMN id SET DEFAULT nextval('public.email_settings_id_seq'::regclass);


--
-- Name: error_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_events ALTER COLUMN id SET DEFAULT nextval('public.error_events_id_seq'::regclass);


--
-- Name: footer_links id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.footer_links ALTER COLUMN id SET DEFAULT nextval('public.footer_links_id_seq'::regclass);


--
-- Name: footer_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.footer_settings ALTER COLUMN id SET DEFAULT nextval('public.footer_settings_id_seq'::regclass);


--
-- Name: footer_social_links id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.footer_social_links ALTER COLUMN id SET DEFAULT nextval('public.footer_social_links_id_seq'::regclass);


--
-- Name: footer_stores id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.footer_stores ALTER COLUMN id SET DEFAULT nextval('public.footer_stores_id_seq'::regclass);


--
-- Name: friendly_id_slugs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendly_id_slugs ALTER COLUMN id SET DEFAULT nextval('public.friendly_id_slugs_id_seq'::regclass);


--
-- Name: google_calendar_integration_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.google_calendar_integration_settings ALTER COLUMN id SET DEFAULT nextval('public.google_calendar_integration_settings_id_seq'::regclass);


--
-- Name: google_maps_integration_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.google_maps_integration_settings ALTER COLUMN id SET DEFAULT nextval('public.google_maps_integration_settings_id_seq'::regclass);


--
-- Name: habitation_audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_audit_logs ALTER COLUMN id SET DEFAULT nextval('public.habitation_audit_logs_id_seq'::regclass);


--
-- Name: habitation_broker_assignments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_broker_assignments ALTER COLUMN id SET DEFAULT nextval('public.habitation_broker_assignments_id_seq'::regclass);


--
-- Name: habitation_exports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_exports ALTER COLUMN id SET DEFAULT nextval('public.habitation_exports_id_seq'::regclass);


--
-- Name: habitation_interactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_interactions ALTER COLUMN id SET DEFAULT nextval('public.habitation_interactions_id_seq'::regclass);


--
-- Name: habitation_photo_shares id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_photo_shares ALTER COLUMN id SET DEFAULT nextval('public.habitation_photo_shares_id_seq'::regclass);


--
-- Name: habitation_share_links id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_share_links ALTER COLUMN id SET DEFAULT nextval('public.habitation_share_links_id_seq'::regclass);


--
-- Name: habitations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitations ALTER COLUMN id SET DEFAULT nextval('public.habitations_id_seq'::regclass);


--
-- Name: home_hero_slides id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.home_hero_slides ALTER COLUMN id SET DEFAULT nextval('public.home_hero_slides_id_seq'::regclass);


--
-- Name: home_section_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.home_section_items ALTER COLUMN id SET DEFAULT nextval('public.home_section_items_id_seq'::regclass);


--
-- Name: home_sections id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.home_sections ALTER COLUMN id SET DEFAULT nextval('public.home_sections_id_seq'::regclass);


--
-- Name: home_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.home_settings ALTER COLUMN id SET DEFAULT nextval('public.home_settings_id_seq'::regclass);


--
-- Name: inbound_webhook_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_webhook_tokens ALTER COLUMN id SET DEFAULT nextval('public.inbound_webhook_tokens_id_seq'::regclass);


--
-- Name: landing_pages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.landing_pages ALTER COLUMN id SET DEFAULT nextval('public.landing_pages_id_seq'::regclass);


--
-- Name: layout_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.layout_settings ALTER COLUMN id SET DEFAULT nextval('public.layout_settings_id_seq'::regclass);


--
-- Name: lead_activities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_activities ALTER COLUMN id SET DEFAULT nextval('public.lead_activities_id_seq'::regclass);


--
-- Name: lead_audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_audit_logs ALTER COLUMN id SET DEFAULT nextval('public.lead_audit_logs_id_seq'::regclass);


--
-- Name: lead_labelings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_labelings ALTER COLUMN id SET DEFAULT nextval('public.lead_labelings_id_seq'::regclass);


--
-- Name: lead_labels id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_labels ALTER COLUMN id SET DEFAULT nextval('public.lead_labels_id_seq'::regclass);


--
-- Name: lead_property_interests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_property_interests ALTER COLUMN id SET DEFAULT nextval('public.lead_property_interests_id_seq'::regclass);


--
-- Name: lead_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_settings ALTER COLUMN id SET DEFAULT nextval('public.lead_settings_id_seq'::regclass);


--
-- Name: leads id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads ALTER COLUMN id SET DEFAULT nextval('public.leads_id_seq'::regclass);


--
-- Name: location_pings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location_pings ALTER COLUMN id SET DEFAULT nextval('public.location_pings_id_seq'::regclass);


--
-- Name: manual_checkin_requests id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manual_checkin_requests ALTER COLUMN id SET DEFAULT nextval('public.manual_checkin_requests_id_seq'::regclass);


--
-- Name: marketing_campaigns id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketing_campaigns ALTER COLUMN id SET DEFAULT nextval('public.marketing_campaigns_id_seq'::regclass);


--
-- Name: meta_facebook_pages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meta_facebook_pages ALTER COLUMN id SET DEFAULT nextval('public.meta_facebook_pages_id_seq'::regclass);


--
-- Name: meta_lead_forms id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meta_lead_forms ALTER COLUMN id SET DEFAULT nextval('public.meta_lead_forms_id_seq'::regclass);


--
-- Name: notification_template_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_template_settings ALTER COLUMN id SET DEFAULT nextval('public.notification_template_settings_id_seq'::regclass);


--
-- Name: photography_schedule_blocks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.photography_schedule_blocks ALTER COLUMN id SET DEFAULT nextval('public.photography_schedule_blocks_id_seq'::regclass);


--
-- Name: portal_integration_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_integration_events ALTER COLUMN id SET DEFAULT nextval('public.portal_integration_events_id_seq'::regclass);


--
-- Name: portal_integrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_integrations ALTER COLUMN id SET DEFAULT nextval('public.portal_integrations_id_seq'::regclass);


--
-- Name: portal_listing_states id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_listing_states ALTER COLUMN id SET DEFAULT nextval('public.portal_listing_states_id_seq'::regclass);


--
-- Name: presentation_cards id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presentation_cards ALTER COLUMN id SET DEFAULT nextval('public.presentation_cards_id_seq'::regclass);


--
-- Name: profiles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles ALTER COLUMN id SET DEFAULT nextval('public.profiles_id_seq'::regclass);


--
-- Name: property_pages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_pages ALTER COLUMN id SET DEFAULT nextval('public.property_pages_id_seq'::regclass);


--
-- Name: property_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_settings ALTER COLUMN id SET DEFAULT nextval('public.property_settings_id_seq'::regclass);


--
-- Name: proposals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proposals ALTER COLUMN id SET DEFAULT nextval('public.proposals_id_seq'::regclass);


--
-- Name: proprietors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proprietors ALTER COLUMN id SET DEFAULT nextval('public.proprietors_id_seq'::regclass);


--
-- Name: public_navigation_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.public_navigation_events ALTER COLUMN id SET DEFAULT nextval('public.public_navigation_events_id_seq'::regclass);


--
-- Name: public_navigation_sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.public_navigation_sessions ALTER COLUMN id SET DEFAULT nextval('public.public_navigation_sessions_id_seq'::regclass);


--
-- Name: push_delivery_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_delivery_events ALTER COLUMN id SET DEFAULT nextval('public.push_delivery_events_id_seq'::regclass);


--
-- Name: push_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_settings ALTER COLUMN id SET DEFAULT nextval('public.push_settings_id_seq'::regclass);


--
-- Name: push_subscriptions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions ALTER COLUMN id SET DEFAULT nextval('public.push_subscriptions_id_seq'::regclass);


--
-- Name: secure_links id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.secure_links ALTER COLUMN id SET DEFAULT nextval('public.secure_links_id_seq'::regclass);


--
-- Name: seo_change_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_change_logs ALTER COLUMN id SET DEFAULT nextval('public.seo_change_logs_id_seq'::regclass);


--
-- Name: seo_conversion_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_conversion_events ALTER COLUMN id SET DEFAULT nextval('public.seo_conversion_events_id_seq'::regclass);


--
-- Name: seo_focus_keywords id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_focus_keywords ALTER COLUMN id SET DEFAULT nextval('public.seo_focus_keywords_id_seq'::regclass);


--
-- Name: seo_page_visits id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_page_visits ALTER COLUMN id SET DEFAULT nextval('public.seo_page_visits_id_seq'::regclass);


--
-- Name: seo_redirects id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_redirects ALTER COLUMN id SET DEFAULT nextval('public.seo_redirects_id_seq'::regclass);


--
-- Name: seo_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_settings ALTER COLUMN id SET DEFAULT nextval('public.seo_settings_id_seq'::regclass);


--
-- Name: settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings ALTER COLUMN id SET DEFAULT nextval('public.settings_id_seq'::regclass);


--
-- Name: solid_queue_blocked_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_blocked_executions_id_seq'::regclass);


--
-- Name: solid_queue_claimed_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_claimed_executions_id_seq'::regclass);


--
-- Name: solid_queue_failed_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_failed_executions_id_seq'::regclass);


--
-- Name: solid_queue_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_jobs ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_jobs_id_seq'::regclass);


--
-- Name: solid_queue_pauses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_pauses ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_pauses_id_seq'::regclass);


--
-- Name: solid_queue_processes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_processes ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_processes_id_seq'::regclass);


--
-- Name: solid_queue_ready_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_ready_executions_id_seq'::regclass);


--
-- Name: solid_queue_recurring_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_recurring_executions_id_seq'::regclass);


--
-- Name: solid_queue_recurring_tasks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_tasks ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_recurring_tasks_id_seq'::regclass);


--
-- Name: solid_queue_scheduled_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_scheduled_executions_id_seq'::regclass);


--
-- Name: solid_queue_semaphores id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_semaphores ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_semaphores_id_seq'::regclass);


--
-- Name: storage_integration_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.storage_integration_settings ALTER COLUMN id SET DEFAULT nextval('public.storage_integration_settings_id_seq'::regclass);


--
-- Name: store_shifts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_shifts ALTER COLUMN id SET DEFAULT nextval('public.store_shifts_id_seq'::regclass);


--
-- Name: stores id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stores ALTER COLUMN id SET DEFAULT nextval('public.stores_id_seq'::regclass);


--
-- Name: system_notification_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_notification_settings ALTER COLUMN id SET DEFAULT nextval('public.system_notification_settings_id_seq'::regclass);


--
-- Name: tasks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks ALTER COLUMN id SET DEFAULT nextval('public.tasks_id_seq'::regclass);


--
-- Name: tenants id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants ALTER COLUMN id SET DEFAULT nextval('public.tenants_id_seq'::regclass);


--
-- Name: trusted_devices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trusted_devices ALTER COLUMN id SET DEFAULT nextval('public.trusted_devices_id_seq'::regclass);


--
-- Name: user_meta_integrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_meta_integrations ALTER COLUMN id SET DEFAULT nextval('public.user_meta_integrations_id_seq'::regclass);


--
-- Name: vista_file_assets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vista_file_assets ALTER COLUMN id SET DEFAULT nextval('public.vista_file_assets_id_seq'::regclass);


--
-- Name: vista_import_batches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vista_import_batches ALTER COLUMN id SET DEFAULT nextval('public.vista_import_batches_id_seq'::regclass);


--
-- Name: vista_raw_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vista_raw_records ALTER COLUMN id SET DEFAULT nextval('public.vista_raw_records_id_seq'::regclass);


--
-- Name: webhook_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_settings ALTER COLUMN id SET DEFAULT nextval('public.webhook_settings_id_seq'::regclass);


--
-- Name: whatsapp_business_integrations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_business_integrations ALTER COLUMN id SET DEFAULT nextval('public.whatsapp_business_integrations_id_seq'::regclass);


--
-- Name: whatsapp_campaign_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_messages ALTER COLUMN id SET DEFAULT nextval('public.whatsapp_campaign_messages_id_seq'::regclass);


--
-- Name: whatsapp_campaign_recipients id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_recipients ALTER COLUMN id SET DEFAULT nextval('public.whatsapp_campaign_recipients_id_seq'::regclass);


--
-- Name: whatsapp_campaign_unsubscribes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_unsubscribes ALTER COLUMN id SET DEFAULT nextval('public.whatsapp_campaign_unsubscribes_id_seq'::regclass);


--
-- Name: whatsapp_campaigns id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaigns ALTER COLUMN id SET DEFAULT nextval('public.whatsapp_campaigns_id_seq'::regclass);


--
-- Name: whatsapp_conversations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_conversations ALTER COLUMN id SET DEFAULT nextval('public.whatsapp_conversations_id_seq'::regclass);


--
-- Name: whatsapp_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_messages ALTER COLUMN id SET DEFAULT nextval('public.whatsapp_messages_id_seq'::regclass);


--
-- Name: whatsapp_sender_numbers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_sender_numbers ALTER COLUMN id SET DEFAULT nextval('public.whatsapp_sender_numbers_id_seq'::regclass);


--
-- Name: whatsapp_templates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_templates ALTER COLUMN id SET DEFAULT nextval('public.whatsapp_templates_id_seq'::regclass);


--
-- Name: access_audit_logs access_audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_audit_logs
    ADD CONSTRAINT access_audit_logs_pkey PRIMARY KEY (id);


--
-- Name: access_control_rules access_control_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_control_rules
    ADD CONSTRAINT access_control_rules_pkey PRIMARY KEY (id);


--
-- Name: account_memberships account_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_memberships
    ADD CONSTRAINT account_memberships_pkey PRIMARY KEY (id);


--
-- Name: action_text_rich_texts action_text_rich_texts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.action_text_rich_texts
    ADD CONSTRAINT action_text_rich_texts_pkey PRIMARY KEY (id);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: addresses addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.addresses
    ADD CONSTRAINT addresses_pkey PRIMARY KEY (id);


--
-- Name: admin_users admin_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT admin_users_pkey PRIMARY KEY (id);


--
-- Name: admin_users admin_users_profile_required_unless_system_admin; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.admin_users
    ADD CONSTRAINT admin_users_profile_required_unless_system_admin CHECK (((super_admin = true) OR (profile_id IS NOT NULL))) NOT VALID;


--
-- Name: ai_property_suggestions ai_property_suggestions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_property_suggestions
    ADD CONSTRAINT ai_property_suggestions_pkey PRIMARY KEY (id);


--
-- Name: appointments appointments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: attribute_options attribute_options_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attribute_options
    ADD CONSTRAINT attribute_options_pkey PRIMARY KEY (id);


--
-- Name: automation_events automation_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_events
    ADD CONSTRAINT automation_events_pkey PRIMARY KEY (id);


--
-- Name: automation_execution_steps automation_execution_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_execution_steps
    ADD CONSTRAINT automation_execution_steps_pkey PRIMARY KEY (id);


--
-- Name: automation_executions automation_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_executions
    ADD CONSTRAINT automation_executions_pkey PRIMARY KEY (id);


--
-- Name: automation_rules automation_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_rules
    ADD CONSTRAINT automation_rules_pkey PRIMARY KEY (id);


--
-- Name: automation_runs automation_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_runs
    ADD CONSTRAINT automation_runs_pkey PRIMARY KEY (id);


--
-- Name: automation_webhook_deliveries automation_webhook_deliveries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_webhook_deliveries
    ADD CONSTRAINT automation_webhook_deliveries_pkey PRIMARY KEY (id);


--
-- Name: automation_workflow_versions automation_workflow_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_workflow_versions
    ADD CONSTRAINT automation_workflow_versions_pkey PRIMARY KEY (id);


--
-- Name: automation_workflows automation_workflows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_workflows
    ADD CONSTRAINT automation_workflows_pkey PRIMARY KEY (id);


--
-- Name: banners banners_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.banners
    ADD CONSTRAINT banners_pkey PRIMARY KEY (id);


--
-- Name: captacao_goals captacao_goals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.captacao_goals
    ADD CONSTRAINT captacao_goals_pkey PRIMARY KEY (id);


--
-- Name: captacoes captacoes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.captacoes
    ADD CONSTRAINT captacoes_pkey PRIMARY KEY (id);


--
-- Name: check_ins check_ins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_ins
    ADD CONSTRAINT check_ins_pkey PRIMARY KEY (id);


--
-- Name: checkin_audit_logs checkin_audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checkin_audit_logs
    ADD CONSTRAINT checkin_audit_logs_pkey PRIMARY KEY (id);


--
-- Name: client_interactions client_interactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_interactions
    ADD CONSTRAINT client_interactions_pkey PRIMARY KEY (id);


--
-- Name: client_property_interests client_property_interests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_property_interests
    ADD CONSTRAINT client_property_interests_pkey PRIMARY KEY (id);


--
-- Name: constructors constructors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.constructors
    ADD CONSTRAINT constructors_pkey PRIMARY KEY (id);


--
-- Name: contact_settings contact_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contact_settings
    ADD CONSTRAINT contact_settings_pkey PRIMARY KEY (id);


--
-- Name: crm_appointments crm_appointments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_appointments
    ADD CONSTRAINT crm_appointments_pkey PRIMARY KEY (id);


--
-- Name: crm_contacts crm_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_contacts
    ADD CONSTRAINT crm_contacts_pkey PRIMARY KEY (id);


--
-- Name: data_export_audit_logs data_export_audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_export_audit_logs
    ADD CONSTRAINT data_export_audit_logs_pkey PRIMARY KEY (id);


--
-- Name: distribution_rule_agents distribution_rule_agents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.distribution_rule_agents
    ADD CONSTRAINT distribution_rule_agents_pkey PRIMARY KEY (id);


--
-- Name: distribution_rules distribution_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.distribution_rules
    ADD CONSTRAINT distribution_rules_pkey PRIMARY KEY (id);


--
-- Name: email_settings email_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_settings
    ADD CONSTRAINT email_settings_pkey PRIMARY KEY (id);


--
-- Name: error_events error_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_events
    ADD CONSTRAINT error_events_pkey PRIMARY KEY (id);


--
-- Name: footer_links footer_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.footer_links
    ADD CONSTRAINT footer_links_pkey PRIMARY KEY (id);


--
-- Name: footer_settings footer_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.footer_settings
    ADD CONSTRAINT footer_settings_pkey PRIMARY KEY (id);


--
-- Name: footer_social_links footer_social_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.footer_social_links
    ADD CONSTRAINT footer_social_links_pkey PRIMARY KEY (id);


--
-- Name: footer_stores footer_stores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.footer_stores
    ADD CONSTRAINT footer_stores_pkey PRIMARY KEY (id);


--
-- Name: friendly_id_slugs friendly_id_slugs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.friendly_id_slugs
    ADD CONSTRAINT friendly_id_slugs_pkey PRIMARY KEY (id);


--
-- Name: google_calendar_integration_settings google_calendar_integration_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.google_calendar_integration_settings
    ADD CONSTRAINT google_calendar_integration_settings_pkey PRIMARY KEY (id);


--
-- Name: google_maps_integration_settings google_maps_integration_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.google_maps_integration_settings
    ADD CONSTRAINT google_maps_integration_settings_pkey PRIMARY KEY (id);


--
-- Name: habitation_audit_logs habitation_audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_audit_logs
    ADD CONSTRAINT habitation_audit_logs_pkey PRIMARY KEY (id);


--
-- Name: habitation_broker_assignments habitation_broker_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_broker_assignments
    ADD CONSTRAINT habitation_broker_assignments_pkey PRIMARY KEY (id);


--
-- Name: habitation_exports habitation_exports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_exports
    ADD CONSTRAINT habitation_exports_pkey PRIMARY KEY (id);


--
-- Name: habitation_interactions habitation_interactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_interactions
    ADD CONSTRAINT habitation_interactions_pkey PRIMARY KEY (id);


--
-- Name: habitation_photo_shares habitation_photo_shares_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_photo_shares
    ADD CONSTRAINT habitation_photo_shares_pkey PRIMARY KEY (id);


--
-- Name: habitation_share_links habitation_share_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_share_links
    ADD CONSTRAINT habitation_share_links_pkey PRIMARY KEY (id);


--
-- Name: habitations habitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitations
    ADD CONSTRAINT habitations_pkey PRIMARY KEY (id);


--
-- Name: home_hero_slides home_hero_slides_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.home_hero_slides
    ADD CONSTRAINT home_hero_slides_pkey PRIMARY KEY (id);


--
-- Name: home_section_items home_section_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.home_section_items
    ADD CONSTRAINT home_section_items_pkey PRIMARY KEY (id);


--
-- Name: home_sections home_sections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.home_sections
    ADD CONSTRAINT home_sections_pkey PRIMARY KEY (id);


--
-- Name: home_settings home_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.home_settings
    ADD CONSTRAINT home_settings_pkey PRIMARY KEY (id);


--
-- Name: inbound_webhook_tokens inbound_webhook_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_webhook_tokens
    ADD CONSTRAINT inbound_webhook_tokens_pkey PRIMARY KEY (id);


--
-- Name: landing_pages landing_pages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.landing_pages
    ADD CONSTRAINT landing_pages_pkey PRIMARY KEY (id);


--
-- Name: layout_settings layout_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.layout_settings
    ADD CONSTRAINT layout_settings_pkey PRIMARY KEY (id);


--
-- Name: lead_activities lead_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_activities
    ADD CONSTRAINT lead_activities_pkey PRIMARY KEY (id);


--
-- Name: lead_audit_logs lead_audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_audit_logs
    ADD CONSTRAINT lead_audit_logs_pkey PRIMARY KEY (id);


--
-- Name: lead_labelings lead_labelings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_labelings
    ADD CONSTRAINT lead_labelings_pkey PRIMARY KEY (id);


--
-- Name: lead_labels lead_labels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_labels
    ADD CONSTRAINT lead_labels_pkey PRIMARY KEY (id);


--
-- Name: lead_property_interests lead_property_interests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_property_interests
    ADD CONSTRAINT lead_property_interests_pkey PRIMARY KEY (id);


--
-- Name: lead_settings lead_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_settings
    ADD CONSTRAINT lead_settings_pkey PRIMARY KEY (id);


--
-- Name: leads leads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_pkey PRIMARY KEY (id);


--
-- Name: location_pings location_pings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location_pings
    ADD CONSTRAINT location_pings_pkey PRIMARY KEY (id);


--
-- Name: manual_checkin_requests manual_checkin_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manual_checkin_requests
    ADD CONSTRAINT manual_checkin_requests_pkey PRIMARY KEY (id);


--
-- Name: marketing_campaigns marketing_campaigns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketing_campaigns
    ADD CONSTRAINT marketing_campaigns_pkey PRIMARY KEY (id);


--
-- Name: meta_facebook_pages meta_facebook_pages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meta_facebook_pages
    ADD CONSTRAINT meta_facebook_pages_pkey PRIMARY KEY (id);


--
-- Name: meta_lead_forms meta_lead_forms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meta_lead_forms
    ADD CONSTRAINT meta_lead_forms_pkey PRIMARY KEY (id);


--
-- Name: notification_template_settings notification_template_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_template_settings
    ADD CONSTRAINT notification_template_settings_pkey PRIMARY KEY (id);


--
-- Name: photography_schedule_blocks photography_schedule_blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.photography_schedule_blocks
    ADD CONSTRAINT photography_schedule_blocks_pkey PRIMARY KEY (id);


--
-- Name: portal_integration_events portal_integration_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_integration_events
    ADD CONSTRAINT portal_integration_events_pkey PRIMARY KEY (id);


--
-- Name: portal_integrations portal_integrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_integrations
    ADD CONSTRAINT portal_integrations_pkey PRIMARY KEY (id);


--
-- Name: portal_listing_states portal_listing_states_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_listing_states
    ADD CONSTRAINT portal_listing_states_pkey PRIMARY KEY (id);


--
-- Name: presentation_cards presentation_cards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presentation_cards
    ADD CONSTRAINT presentation_cards_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_axis_allowed; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_axis_allowed CHECK (((axis)::text = ANY ((ARRAY['vertical'::character varying, 'horizontal'::character varying])::text[]))) NOT VALID;


--
-- Name: profiles profiles_axis_shape; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_axis_shape CHECK (((((axis)::text = 'vertical'::text) AND (vertical_profile_id IS NULL) AND ("position" IS NOT NULL)) OR (((axis)::text = 'horizontal'::text) AND (vertical_profile_id IS NOT NULL) AND ("position" IS NULL)))) NOT VALID;


--
-- Name: profiles profiles_builtin_axis_governance; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_builtin_axis_governance CHECK (((key IS NULL) OR ((key)::text <> ALL ((ARRAY['tenant_owner'::character varying, 'agent'::character varying])::text[])) OR (((key)::text = ANY ((ARRAY['tenant_owner'::character varying, 'agent'::character varying])::text[])) AND ((axis)::text = 'vertical'::text) AND (vertical_profile_id IS NULL) AND ("position" IS NOT NULL)))) NOT VALID;


--
-- Name: profiles profiles_locked_only_for_builtin_verticals; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_locked_only_for_builtin_verticals CHECK (((locked = false) OR ((key)::text = ANY ((ARRAY['tenant_owner'::character varying, 'agent'::character varying])::text[])))) NOT VALID;


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_vertical_position_governance; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_vertical_position_governance CHECK ((((axis)::text <> 'vertical'::text) OR (((key)::text = 'tenant_owner'::text) AND ("position" = 0) AND (locked = true) AND (vertical_profile_id IS NULL)) OR (((key)::text = 'agent'::text) AND ("position" = 10000) AND (locked = true) AND (vertical_profile_id IS NULL)) OR (((key IS NULL) OR ((key)::text <> ALL ((ARRAY['tenant_owner'::character varying, 'agent'::character varying])::text[]))) AND ("position" > 0) AND ("position" < 10000) AND (vertical_profile_id IS NULL)))) NOT VALID;


--
-- Name: property_pages property_pages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_pages
    ADD CONSTRAINT property_pages_pkey PRIMARY KEY (id);


--
-- Name: property_settings property_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_settings
    ADD CONSTRAINT property_settings_pkey PRIMARY KEY (id);


--
-- Name: proposals proposals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proposals
    ADD CONSTRAINT proposals_pkey PRIMARY KEY (id);


--
-- Name: proprietors proprietors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proprietors
    ADD CONSTRAINT proprietors_pkey PRIMARY KEY (id);


--
-- Name: public_navigation_events public_navigation_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.public_navigation_events
    ADD CONSTRAINT public_navigation_events_pkey PRIMARY KEY (id);


--
-- Name: public_navigation_sessions public_navigation_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.public_navigation_sessions
    ADD CONSTRAINT public_navigation_sessions_pkey PRIMARY KEY (id);


--
-- Name: push_delivery_events push_delivery_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_delivery_events
    ADD CONSTRAINT push_delivery_events_pkey PRIMARY KEY (id);


--
-- Name: push_settings push_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_settings
    ADD CONSTRAINT push_settings_pkey PRIMARY KEY (id);


--
-- Name: push_subscriptions push_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: secure_links secure_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.secure_links
    ADD CONSTRAINT secure_links_pkey PRIMARY KEY (id);


--
-- Name: seo_change_logs seo_change_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_change_logs
    ADD CONSTRAINT seo_change_logs_pkey PRIMARY KEY (id);


--
-- Name: seo_conversion_events seo_conversion_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_conversion_events
    ADD CONSTRAINT seo_conversion_events_pkey PRIMARY KEY (id);


--
-- Name: seo_focus_keywords seo_focus_keywords_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_focus_keywords
    ADD CONSTRAINT seo_focus_keywords_pkey PRIMARY KEY (id);


--
-- Name: seo_page_visits seo_page_visits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_page_visits
    ADD CONSTRAINT seo_page_visits_pkey PRIMARY KEY (id);


--
-- Name: seo_redirects seo_redirects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_redirects
    ADD CONSTRAINT seo_redirects_pkey PRIMARY KEY (id);


--
-- Name: seo_settings seo_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_settings
    ADD CONSTRAINT seo_settings_pkey PRIMARY KEY (id);


--
-- Name: settings settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT settings_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_blocked_executions solid_queue_blocked_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions
    ADD CONSTRAINT solid_queue_blocked_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_claimed_executions solid_queue_claimed_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions
    ADD CONSTRAINT solid_queue_claimed_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_failed_executions solid_queue_failed_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions
    ADD CONSTRAINT solid_queue_failed_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_jobs solid_queue_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_jobs
    ADD CONSTRAINT solid_queue_jobs_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_pauses solid_queue_pauses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_pauses
    ADD CONSTRAINT solid_queue_pauses_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_processes solid_queue_processes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_processes
    ADD CONSTRAINT solid_queue_processes_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_ready_executions solid_queue_ready_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions
    ADD CONSTRAINT solid_queue_ready_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_recurring_executions solid_queue_recurring_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions
    ADD CONSTRAINT solid_queue_recurring_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_recurring_tasks solid_queue_recurring_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_tasks
    ADD CONSTRAINT solid_queue_recurring_tasks_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_scheduled_executions solid_queue_scheduled_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions
    ADD CONSTRAINT solid_queue_scheduled_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_semaphores solid_queue_semaphores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_semaphores
    ADD CONSTRAINT solid_queue_semaphores_pkey PRIMARY KEY (id);


--
-- Name: storage_integration_settings storage_integration_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.storage_integration_settings
    ADD CONSTRAINT storage_integration_settings_pkey PRIMARY KEY (id);


--
-- Name: store_shifts store_shifts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_shifts
    ADD CONSTRAINT store_shifts_pkey PRIMARY KEY (id);


--
-- Name: stores stores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT stores_pkey PRIMARY KEY (id);


--
-- Name: system_notification_settings system_notification_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_notification_settings
    ADD CONSTRAINT system_notification_settings_pkey PRIMARY KEY (id);


--
-- Name: tasks tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_pkey PRIMARY KEY (id);


--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (id);


--
-- Name: trusted_devices trusted_devices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trusted_devices
    ADD CONSTRAINT trusted_devices_pkey PRIMARY KEY (id);


--
-- Name: user_meta_integrations user_meta_integrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_meta_integrations
    ADD CONSTRAINT user_meta_integrations_pkey PRIMARY KEY (id);


--
-- Name: vista_file_assets vista_file_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vista_file_assets
    ADD CONSTRAINT vista_file_assets_pkey PRIMARY KEY (id);


--
-- Name: vista_import_batches vista_import_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vista_import_batches
    ADD CONSTRAINT vista_import_batches_pkey PRIMARY KEY (id);


--
-- Name: vista_raw_records vista_raw_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vista_raw_records
    ADD CONSTRAINT vista_raw_records_pkey PRIMARY KEY (id);


--
-- Name: webhook_settings webhook_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_settings
    ADD CONSTRAINT webhook_settings_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_business_integrations whatsapp_business_integrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_business_integrations
    ADD CONSTRAINT whatsapp_business_integrations_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_campaign_messages whatsapp_campaign_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_messages
    ADD CONSTRAINT whatsapp_campaign_messages_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_campaign_recipients whatsapp_campaign_recipients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_recipients
    ADD CONSTRAINT whatsapp_campaign_recipients_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_campaign_unsubscribes whatsapp_campaign_unsubscribes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_unsubscribes
    ADD CONSTRAINT whatsapp_campaign_unsubscribes_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_campaigns whatsapp_campaigns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaigns
    ADD CONSTRAINT whatsapp_campaigns_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_conversations whatsapp_conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_conversations
    ADD CONSTRAINT whatsapp_conversations_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_messages whatsapp_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_messages
    ADD CONSTRAINT whatsapp_messages_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_sender_numbers whatsapp_sender_numbers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_sender_numbers
    ADD CONSTRAINT whatsapp_sender_numbers_pkey PRIMARY KEY (id);


--
-- Name: whatsapp_templates whatsapp_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_templates
    ADD CONSTRAINT whatsapp_templates_pkey PRIMARY KEY (id);


--
-- Name: idx_account_memberships_live_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_account_memberships_live_email ON public.account_memberships USING btree (tenant_id, lower((invited_email)::text)) WHERE (status <> 2);


--
-- Name: idx_account_memberships_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_account_memberships_on_token_digest ON public.account_memberships USING btree (invite_token_digest);


--
-- Name: idx_active_storage_habitation_photo_records; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_active_storage_habitation_photo_records ON public.active_storage_attachments USING btree (record_type, name, record_id) WHERE (((record_type)::text = 'Habitation'::text) AND ((name)::text = 'photos'::text));


--
-- Name: idx_admin_users_one_mirror_per_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_admin_users_one_mirror_per_tenant ON public.admin_users USING btree (primary_admin_user_id, tenant_id) WHERE (primary_admin_user_id IS NOT NULL);


--
-- Name: idx_automation_events_lead_name_occurred_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_automation_events_lead_name_occurred_at ON public.automation_events USING btree (lead_id, name, occurred_at);


--
-- Name: idx_automation_execution_steps_on_execution_node; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_automation_execution_steps_on_execution_node ON public.automation_execution_steps USING btree (automation_execution_id, node_id);


--
-- Name: idx_automation_executions_workflow_lead_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_automation_executions_workflow_lead_status ON public.automation_executions USING btree (automation_workflow_id, lead_id, status);


--
-- Name: idx_automation_workflow_versions_on_workflow_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_automation_workflow_versions_on_workflow_status ON public.automation_workflow_versions USING btree (automation_workflow_id, status);


--
-- Name: idx_automation_workflow_versions_unique_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_automation_workflow_versions_unique_number ON public.automation_workflow_versions USING btree (automation_workflow_id, version_number);


--
-- Name: idx_checkins_store_turno_status_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checkins_store_turno_status_date ON public.check_ins USING btree (store_id, turno, status_chegada, checked_in_at);


--
-- Name: idx_cpi_client_habitation_codes; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cpi_client_habitation_codes ON public.client_property_interests USING btree (vista_client_code, vista_habitation_code);


--
-- Name: idx_dist_rule_agents_on_rule_and_admin; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_dist_rule_agents_on_rule_and_admin ON public.distribution_rule_agents USING btree (distribution_rule_id, admin_user_id);


--
-- Name: idx_distribution_rules_tenant_auto_update; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_distribution_rules_tenant_auto_update ON public.distribution_rules USING btree (tenant_id, auto_update_agents_enabled);


--
-- Name: idx_email_settings_on_tenant_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_email_settings_on_tenant_unique ON public.email_settings USING btree (tenant_id) WHERE (tenant_id IS NOT NULL);


--
-- Name: idx_hab_share_links_hab_admin_exp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hab_share_links_hab_admin_exp ON public.habitation_share_links USING btree (habitation_id, admin_user_id, expires_at);


--
-- Name: idx_habitations_categoria_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_habitations_categoria_status ON public.habitations USING btree (categoria, status);


--
-- Name: idx_habitations_exibir_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_habitations_exibir_status ON public.habitations USING btree (exibir_no_site_flag, status);


--
-- Name: idx_habitations_geolocation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_habitations_geolocation ON public.habitations USING btree (latitude, longitude);


--
-- Name: idx_habitations_home_corporate_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_habitations_home_corporate_order ON public.habitations USING btree (home_corporate_flag, home_corporate_position);


--
-- Name: idx_habitations_localizacao_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_habitations_localizacao_status ON public.habitations USING btree (cidade, bairro, status);


--
-- Name: idx_habitations_public_development_units; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_habitations_public_development_units ON public.habitations USING btree (tenant_id, codigo_empreendimento, exibir_no_site_flag, status) WHERE (codigo_empreendimento IS NOT NULL);


--
-- Name: idx_habitations_public_tenant_status_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_habitations_public_tenant_status_order ON public.habitations USING btree (tenant_id, exibir_no_site_flag, status, data_atualizacao_crm DESC, created_at DESC);


--
-- Name: idx_habitations_status_categoria_cidade; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_habitations_status_categoria_cidade ON public.habitations USING btree (status, categoria, cidade);


--
-- Name: idx_habitations_venda_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_habitations_venda_status ON public.habitations USING btree (valor_venda_cents, status);


--
-- Name: idx_hba_on_vista_payload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_hba_on_vista_payload ON public.habitation_broker_assignments USING gin (vista_payload);


--
-- Name: idx_hba_vista_batch_source_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_hba_vista_batch_source_key ON public.habitation_broker_assignments USING btree (vista_import_batch_id, vista_source_key) WHERE (vista_source_key IS NOT NULL);


--
-- Name: idx_meta_forms_on_page_and_form_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_meta_forms_on_page_and_form_id ON public.meta_lead_forms USING btree (meta_facebook_page_id, form_id);


--
-- Name: idx_meta_pages_on_integration_and_page_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_meta_pages_on_integration_and_page_id ON public.meta_facebook_pages USING btree (user_meta_integration_id, page_id);


--
-- Name: idx_meta_pages_on_page_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meta_pages_on_page_id ON public.meta_facebook_pages USING btree (page_id);


--
-- Name: idx_notification_template_settings_unique_purpose; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_notification_template_settings_unique_purpose ON public.notification_template_settings USING btree (tenant_id, channel, purpose);


--
-- Name: idx_on_automation_execution_step_id_3b66d0bae6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_automation_execution_step_id_3b66d0bae6 ON public.automation_webhook_deliveries USING btree (automation_execution_step_id);


--
-- Name: idx_on_broker_capture_fallback_admin_user_id_a0c8e86b6d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_broker_capture_fallback_admin_user_id_a0c8e86b6d ON public.property_settings USING btree (broker_capture_fallback_admin_user_id);


--
-- Name: idx_on_connected_by_admin_user_id_2487a8ba72; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_connected_by_admin_user_id_2487a8ba72 ON public.whatsapp_business_integrations USING btree (connected_by_admin_user_id);


--
-- Name: idx_on_portal_external_listing_id_a9202d155f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_portal_external_listing_id_a9202d155f ON public.portal_integration_events USING btree (portal, external_listing_id);


--
-- Name: idx_on_tenant_id_automation_execution_id_34e6c3acad; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_tenant_id_automation_execution_id_34e6c3acad ON public.automation_execution_steps USING btree (tenant_id, automation_execution_id);


--
-- Name: idx_on_tenant_id_automation_workflow_id_4d4759b95a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_tenant_id_automation_workflow_id_4d4759b95a ON public.automation_executions USING btree (tenant_id, automation_workflow_id);


--
-- Name: idx_on_tenant_id_automation_workflow_id_d14f88f362; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_tenant_id_automation_workflow_id_d14f88f362 ON public.automation_workflow_versions USING btree (tenant_id, automation_workflow_id);


--
-- Name: idx_on_tenant_id_phone_number_id_9c3acbd0a4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_tenant_id_phone_number_id_9c3acbd0a4 ON public.whatsapp_business_integrations USING btree (tenant_id, phone_number_id);


--
-- Name: idx_on_tenant_id_whatsapp_campaign_id_234de3ba14; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_tenant_id_whatsapp_campaign_id_234de3ba14 ON public.whatsapp_campaign_recipients USING btree (tenant_id, whatsapp_campaign_id);


--
-- Name: idx_on_tenant_id_whatsapp_campaign_id_4ce4f8680f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_tenant_id_whatsapp_campaign_id_4ce4f8680f ON public.whatsapp_campaign_messages USING btree (tenant_id, whatsapp_campaign_id);


--
-- Name: idx_on_tenant_id_whatsapp_campaign_id_8359110939; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_tenant_id_whatsapp_campaign_id_8359110939 ON public.whatsapp_campaign_unsubscribes USING btree (tenant_id, whatsapp_campaign_id);


--
-- Name: idx_on_tenant_id_whatsapp_conversation_id_37b8916511; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_tenant_id_whatsapp_conversation_id_37b8916511 ON public.whatsapp_messages USING btree (tenant_id, whatsapp_conversation_id);


--
-- Name: idx_on_vista_client_code_occurred_at_61bc0ad3da; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_vista_client_code_occurred_at_61bc0ad3da ON public.habitation_interactions USING btree (vista_client_code, occurred_at);


--
-- Name: idx_on_vista_habitation_code_occurred_at_914b53c11a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_vista_habitation_code_occurred_at_914b53c11a ON public.habitation_interactions USING btree (vista_habitation_code, occurred_at);


--
-- Name: idx_on_vista_habitation_code_occurred_at_965a8d5412; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_vista_habitation_code_occurred_at_965a8d5412 ON public.client_interactions USING btree (vista_habitation_code, occurred_at);


--
-- Name: idx_on_whatsapp_business_integration_id_1506c99b7b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_whatsapp_business_integration_id_1506c99b7b ON public.whatsapp_sender_numbers USING btree (whatsapp_business_integration_id);


--
-- Name: idx_on_whatsapp_conversation_id_created_at_858d582181; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_whatsapp_conversation_id_created_at_858d582181 ON public.whatsapp_messages USING btree (whatsapp_conversation_id, created_at);


--
-- Name: idx_portal_integrations_on_tenant_and_portal; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_portal_integrations_on_tenant_and_portal ON public.portal_integrations USING btree (tenant_id, portal);


--
-- Name: idx_portal_listing_states_tenant_portal_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_portal_listing_states_tenant_portal_code ON public.portal_listing_states USING btree (tenant_id, portal, habitation_code);


--
-- Name: idx_portal_listing_states_tenant_portal_external; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_portal_listing_states_tenant_portal_external ON public.portal_listing_states USING btree (tenant_id, portal, external_listing_id) WHERE (external_listing_id IS NOT NULL);


--
-- Name: idx_property_settings_on_tenant_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_property_settings_on_tenant_unique ON public.property_settings USING btree (tenant_id) WHERE (tenant_id IS NOT NULL);


--
-- Name: idx_proprietors_on_tenant_cpf_digits; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proprietors_on_tenant_cpf_digits ON public.proprietors USING btree (tenant_id, cpf_cnpj_digits);


--
-- Name: idx_proprietors_on_tenant_lower_trim_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_proprietors_on_tenant_lower_trim_name ON public.proprietors USING btree (tenant_id, lower(TRIM(BOTH FROM name)));


--
-- Name: idx_public_nav_events_habitation_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_public_nav_events_habitation_name ON public.public_navigation_events USING btree (habitation_id, name);


--
-- Name: idx_public_nav_events_lead_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_public_nav_events_lead_name ON public.public_navigation_events USING btree (lead_id, name);


--
-- Name: idx_public_nav_events_session_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_public_nav_events_session_time ON public.public_navigation_events USING btree (public_navigation_session_id, occurred_at);


--
-- Name: idx_settings_global_key_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_settings_global_key_unique ON public.settings USING btree (key) WHERE (tenant_id IS NULL);


--
-- Name: idx_settings_tenant_key_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_settings_tenant_key_unique ON public.settings USING btree (tenant_id, key) WHERE (tenant_id IS NOT NULL);


--
-- Name: idx_store_shifts_agent_day_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_store_shifts_agent_day_active ON public.store_shifts USING btree (admin_user_id, day_of_week, active);


--
-- Name: idx_unique_active_checkin_per_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_unique_active_checkin_per_user ON public.check_ins USING btree (admin_user_id) WHERE (status = 0);


--
-- Name: idx_user_meta_integrations_on_user_and_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_user_meta_integrations_on_user_and_tenant ON public.user_meta_integrations USING btree (admin_user_id, tenant_id);


--
-- Name: idx_vista_file_assets_lookup_for_reuse; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vista_file_assets_lookup_for_reuse ON public.vista_file_assets USING btree (vista_import_batch_id, kind, codigo_imovel, filename);


--
-- Name: idx_vista_file_assets_unique_source; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_vista_file_assets_unique_source ON public.vista_file_assets USING btree (vista_import_batch_id, table_name, source_path);


--
-- Name: idx_vista_raw_records_batch_table_row; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_vista_raw_records_batch_table_row ON public.vista_raw_records USING btree (vista_import_batch_id, table_name, row_index);


--
-- Name: idx_wa_campaign_messages_dispatch_scan; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_campaign_messages_dispatch_scan ON public.whatsapp_campaign_messages USING btree (whatsapp_campaign_id, status, created_at);


--
-- Name: idx_wa_campaign_messages_on_campaign_lead; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_campaign_messages_on_campaign_lead ON public.whatsapp_campaign_messages USING btree (whatsapp_campaign_id, lead_id);


--
-- Name: idx_wa_campaign_messages_on_recipient; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_campaign_messages_on_recipient ON public.whatsapp_campaign_messages USING btree (whatsapp_campaign_recipient_id);


--
-- Name: idx_wa_campaign_recipients_on_campaign_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_wa_campaign_recipients_on_campaign_phone ON public.whatsapp_campaign_recipients USING btree (whatsapp_campaign_id, phone_number);


--
-- Name: idx_wa_conversations_on_tenant_recent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_conversations_on_tenant_recent ON public.whatsapp_conversations USING btree (tenant_id, last_message_at DESC NULLS LAST, updated_at DESC);


--
-- Name: idx_wa_conversations_on_tenant_unread; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_conversations_on_tenant_unread ON public.whatsapp_conversations USING btree (tenant_id, unread_count) WHERE (unread_count > 0);


--
-- Name: idx_wa_sender_numbers_campaign_usage; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_sender_numbers_campaign_usage ON public.whatsapp_sender_numbers USING btree (tenant_id, active, use_for_campaigns);


--
-- Name: idx_wa_sender_numbers_notification_usage; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_sender_numbers_notification_usage ON public.whatsapp_sender_numbers USING btree (tenant_id, active, use_for_notifications);


--
-- Name: idx_wa_sender_numbers_on_tenant_and_phone_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_wa_sender_numbers_on_tenant_and_phone_number ON public.whatsapp_sender_numbers USING btree (tenant_id, phone_number_id);


--
-- Name: idx_wa_unsub_active_sender_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_wa_unsub_active_sender_phone ON public.whatsapp_campaign_unsubscribes USING btree (whatsapp_sender_number_id, phone_number) WHERE (reenabled_at IS NULL);


--
-- Name: idx_wa_unsub_campaign; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_unsub_campaign ON public.whatsapp_campaign_unsubscribes USING btree (whatsapp_campaign_id);


--
-- Name: idx_wa_unsub_campaign_message; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_unsub_campaign_message ON public.whatsapp_campaign_unsubscribes USING btree (whatsapp_campaign_message_id);


--
-- Name: idx_wa_unsub_campaign_recipient; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_unsub_campaign_recipient ON public.whatsapp_campaign_unsubscribes USING btree (whatsapp_campaign_recipient_id);


--
-- Name: idx_wa_unsub_inbound_message; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_unsub_inbound_message ON public.whatsapp_campaign_unsubscribes USING btree (unsubscribed_by_message_id);


--
-- Name: idx_wa_unsub_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_unsub_phone ON public.whatsapp_campaign_unsubscribes USING btree (phone_number);


--
-- Name: idx_wa_unsub_reenabled_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_unsub_reenabled_by ON public.whatsapp_campaign_unsubscribes USING btree (reenabled_by_id);


--
-- Name: idx_wa_unsub_sender; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_unsub_sender ON public.whatsapp_campaign_unsubscribes USING btree (whatsapp_sender_number_id);


--
-- Name: idx_wa_unsub_unsubscribed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wa_unsub_unsubscribed_at ON public.whatsapp_campaign_unsubscribes USING btree (unsubscribed_at);


--
-- Name: idx_whatsapp_templates_on_tenant_waba_name_language; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_whatsapp_templates_on_tenant_waba_name_language ON public.whatsapp_templates USING btree (tenant_id, waba_id, name, language);


--
-- Name: idx_whatsapp_templates_on_tenant_waba_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_whatsapp_templates_on_tenant_waba_status ON public.whatsapp_templates USING btree (tenant_id, waba_id, status);


--
-- Name: index_access_audit_logs_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_access_audit_logs_on_admin_user_id ON public.access_audit_logs USING btree (admin_user_id);


--
-- Name: index_access_audit_logs_on_admin_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_access_audit_logs_on_admin_user_id_and_created_at ON public.access_audit_logs USING btree (admin_user_id, created_at);


--
-- Name: index_access_audit_logs_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_access_audit_logs_on_created_at ON public.access_audit_logs USING btree (created_at);


--
-- Name: index_access_audit_logs_on_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_access_audit_logs_on_event_type ON public.access_audit_logs USING btree (event_type);


--
-- Name: index_access_audit_logs_on_ip; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_access_audit_logs_on_ip ON public.access_audit_logs USING btree (ip);


--
-- Name: index_access_audit_logs_on_result; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_access_audit_logs_on_result ON public.access_audit_logs USING btree (result);


--
-- Name: index_access_audit_logs_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_access_audit_logs_on_tenant_id ON public.access_audit_logs USING btree (tenant_id);


--
-- Name: index_access_control_rules_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_access_control_rules_on_admin_user_id ON public.access_control_rules USING btree (admin_user_id);


--
-- Name: index_access_control_rules_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_access_control_rules_on_created_by_id ON public.access_control_rules USING btree (created_by_id);


--
-- Name: index_access_control_rules_on_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_access_control_rules_on_enabled ON public.access_control_rules USING btree (enabled);


--
-- Name: index_access_control_rules_on_profile_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_access_control_rules_on_profile_id ON public.access_control_rules USING btree (profile_id);


--
-- Name: index_access_control_rules_on_rule_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_access_control_rules_on_rule_type ON public.access_control_rules USING btree (rule_type);


--
-- Name: index_access_control_rules_on_scope_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_access_control_rules_on_scope_type ON public.access_control_rules USING btree (scope_type);


--
-- Name: index_access_control_rules_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_access_control_rules_on_tenant_id ON public.access_control_rules USING btree (tenant_id);


--
-- Name: index_access_rules_on_tenant_type_scope_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_access_rules_on_tenant_type_scope_enabled ON public.access_control_rules USING btree (tenant_id, rule_type, scope_type, enabled);


--
-- Name: index_access_rules_on_type_scope_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_access_rules_on_type_scope_enabled ON public.access_control_rules USING btree (rule_type, scope_type, enabled);


--
-- Name: index_account_memberships_on_horizontal_profile_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_memberships_on_horizontal_profile_id ON public.account_memberships USING btree (horizontal_profile_id);


--
-- Name: index_account_memberships_on_invited_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_memberships_on_invited_by_id ON public.account_memberships USING btree (invited_by_id);


--
-- Name: index_account_memberships_on_manager_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_memberships_on_manager_id ON public.account_memberships USING btree (manager_id);


--
-- Name: index_account_memberships_on_member_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_account_memberships_on_member_admin_user_id ON public.account_memberships USING btree (member_admin_user_id);


--
-- Name: index_account_memberships_on_primary_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_memberships_on_primary_admin_user_id ON public.account_memberships USING btree (primary_admin_user_id);


--
-- Name: index_account_memberships_on_profile_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_memberships_on_profile_id ON public.account_memberships USING btree (profile_id);


--
-- Name: index_account_memberships_on_rentals_manager_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_memberships_on_rentals_manager_id ON public.account_memberships USING btree (rentals_manager_id);


--
-- Name: index_account_memberships_on_revoked_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_memberships_on_revoked_by_id ON public.account_memberships USING btree (revoked_by_id);


--
-- Name: index_account_memberships_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_account_memberships_on_tenant_id ON public.account_memberships USING btree (tenant_id);


--
-- Name: index_action_text_rich_texts_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_action_text_rich_texts_uniqueness ON public.action_text_rich_texts USING btree (record_type, record_id, name);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_addresses_on_addressable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_addresses_on_addressable ON public.addresses USING btree (addressable_type, addressable_id);


--
-- Name: index_admin_users_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_active ON public.admin_users USING btree (active);


--
-- Name: index_admin_users_on_default_store_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_default_store_id ON public.admin_users USING btree (default_store_id);


--
-- Name: index_admin_users_on_display_on_site; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_display_on_site ON public.admin_users USING btree (display_on_site);


--
-- Name: index_admin_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_admin_users_on_email ON public.admin_users USING btree (email);


--
-- Name: index_admin_users_on_field_agent_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_field_agent_enabled ON public.admin_users USING btree (field_agent_enabled);


--
-- Name: index_admin_users_on_horizontal_profile_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_horizontal_profile_id ON public.admin_users USING btree (horizontal_profile_id);


--
-- Name: index_admin_users_on_id_and_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_admin_users_on_id_and_tenant_id ON public.admin_users USING btree (id, tenant_id);


--
-- Name: index_admin_users_on_manager_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_manager_id ON public.admin_users USING btree (manager_id);


--
-- Name: index_admin_users_on_manager_id_and_hierarchy_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_manager_id_and_hierarchy_position ON public.admin_users USING btree (manager_id, hierarchy_position);


--
-- Name: index_admin_users_on_primary_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_primary_admin_user_id ON public.admin_users USING btree (primary_admin_user_id);


--
-- Name: index_admin_users_on_profile_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_profile_id ON public.admin_users USING btree (profile_id);


--
-- Name: index_admin_users_on_rentals_manager_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_rentals_manager_id ON public.admin_users USING btree (rentals_manager_id);


--
-- Name: index_admin_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_admin_users_on_reset_password_token ON public.admin_users USING btree (reset_password_token);


--
-- Name: index_admin_users_on_super_admin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_super_admin ON public.admin_users USING btree (super_admin) WHERE (super_admin = true);


--
-- Name: index_admin_users_on_team_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_team_code ON public.admin_users USING btree (team_code);


--
-- Name: index_admin_users_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_tenant_id ON public.admin_users USING btree (tenant_id);


--
-- Name: index_admin_users_on_tenant_id_and_manager_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_tenant_id_and_manager_id ON public.admin_users USING btree (tenant_id, manager_id);


--
-- Name: index_admin_users_on_tenant_id_and_profile_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_tenant_id_and_profile_id ON public.admin_users USING btree (tenant_id, profile_id);


--
-- Name: index_admin_users_on_vista_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_vista_id ON public.admin_users USING btree (vista_id);


--
-- Name: index_admin_users_on_vista_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_vista_import_batch_id ON public.admin_users USING btree (vista_import_batch_id);


--
-- Name: index_admin_users_on_vista_payload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_admin_users_on_vista_payload ON public.admin_users USING gin (vista_payload);


--
-- Name: index_ai_property_suggestions_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_property_suggestions_on_admin_user_id ON public.ai_property_suggestions USING btree (admin_user_id);


--
-- Name: index_ai_property_suggestions_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_property_suggestions_on_habitation_id ON public.ai_property_suggestions USING btree (habitation_id);


--
-- Name: index_ai_property_suggestions_on_habitation_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_property_suggestions_on_habitation_id_and_status ON public.ai_property_suggestions USING btree (habitation_id, status);


--
-- Name: index_appointments_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointments_on_admin_user_id ON public.appointments USING btree (admin_user_id);


--
-- Name: index_appointments_on_admin_user_id_and_starts_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointments_on_admin_user_id_and_starts_at ON public.appointments USING btree (admin_user_id, starts_at);


--
-- Name: index_appointments_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointments_on_habitation_id ON public.appointments USING btree (habitation_id);


--
-- Name: index_appointments_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointments_on_lead_id ON public.appointments USING btree (lead_id);


--
-- Name: index_appointments_on_starts_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointments_on_starts_at ON public.appointments USING btree (starts_at);


--
-- Name: index_appointments_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointments_on_tenant_id ON public.appointments USING btree (tenant_id);


--
-- Name: index_appointments_on_tenant_id_and_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointments_on_tenant_id_and_admin_user_id ON public.appointments USING btree (tenant_id, admin_user_id);


--
-- Name: index_attribute_options_on_context_category_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_attribute_options_on_context_category_lower_name ON public.attribute_options USING btree (tenant_id, lower((name)::text), category, context);


--
-- Name: index_attribute_options_on_context_category_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_attribute_options_on_context_category_position ON public.attribute_options USING btree (tenant_id, context, category, "position");


--
-- Name: index_attribute_options_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_attribute_options_on_tenant_id ON public.attribute_options USING btree (tenant_id);


--
-- Name: index_automation_events_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_events_on_lead_id ON public.automation_events USING btree (lead_id);


--
-- Name: index_automation_events_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_events_on_name ON public.automation_events USING btree (name);


--
-- Name: index_automation_events_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_events_on_status ON public.automation_events USING btree (status);


--
-- Name: index_automation_events_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_events_on_tenant_id ON public.automation_events USING btree (tenant_id);


--
-- Name: index_automation_events_on_tenant_id_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_automation_events_on_tenant_id_and_idempotency_key ON public.automation_events USING btree (tenant_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: index_automation_execs_on_tenant_id_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_automation_execs_on_tenant_id_and_idempotency_key ON public.automation_executions USING btree (tenant_id, idempotency_key) WHERE (idempotency_key IS NOT NULL);


--
-- Name: index_automation_execution_steps_on_automation_execution_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_execution_steps_on_automation_execution_id ON public.automation_execution_steps USING btree (automation_execution_id);


--
-- Name: index_automation_execution_steps_on_scheduled_for; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_execution_steps_on_scheduled_for ON public.automation_execution_steps USING btree (scheduled_for);


--
-- Name: index_automation_execution_steps_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_execution_steps_on_status ON public.automation_execution_steps USING btree (status);


--
-- Name: index_automation_execution_steps_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_execution_steps_on_tenant_id ON public.automation_execution_steps USING btree (tenant_id);


--
-- Name: index_automation_executions_on_automation_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_executions_on_automation_event_id ON public.automation_executions USING btree (automation_event_id);


--
-- Name: index_automation_executions_on_automation_workflow_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_executions_on_automation_workflow_id ON public.automation_executions USING btree (automation_workflow_id);


--
-- Name: index_automation_executions_on_automation_workflow_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_executions_on_automation_workflow_version_id ON public.automation_executions USING btree (automation_workflow_version_id);


--
-- Name: index_automation_executions_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_executions_on_lead_id ON public.automation_executions USING btree (lead_id);


--
-- Name: index_automation_executions_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_executions_on_status ON public.automation_executions USING btree (status);


--
-- Name: index_automation_executions_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_executions_on_tenant_id ON public.automation_executions USING btree (tenant_id);


--
-- Name: index_automation_rules_on_active_and_trigger_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_rules_on_active_and_trigger_event ON public.automation_rules USING btree (active, trigger_event);


--
-- Name: index_automation_rules_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_rules_on_tenant_id ON public.automation_rules USING btree (tenant_id);


--
-- Name: index_automation_rules_on_tenant_id_and_trigger_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_rules_on_tenant_id_and_trigger_event ON public.automation_rules USING btree (tenant_id, trigger_event);


--
-- Name: index_automation_runs_on_automation_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_runs_on_automation_event_id ON public.automation_runs USING btree (automation_event_id);


--
-- Name: index_automation_runs_on_automation_rule_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_runs_on_automation_rule_id ON public.automation_runs USING btree (automation_rule_id);


--
-- Name: index_automation_runs_on_automation_rule_id_and_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_runs_on_automation_rule_id_and_lead_id ON public.automation_runs USING btree (automation_rule_id, lead_id);


--
-- Name: index_automation_runs_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_runs_on_lead_id ON public.automation_runs USING btree (lead_id);


--
-- Name: index_automation_webhook_deliveries_on_automation_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_webhook_deliveries_on_automation_event_id ON public.automation_webhook_deliveries USING btree (automation_event_id);


--
-- Name: index_automation_webhook_deliveries_on_automation_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_webhook_deliveries_on_automation_run_id ON public.automation_webhook_deliveries USING btree (automation_run_id);


--
-- Name: index_automation_webhook_deliveries_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_webhook_deliveries_on_created_at ON public.automation_webhook_deliveries USING btree (created_at);


--
-- Name: index_automation_webhook_deliveries_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_webhook_deliveries_on_lead_id ON public.automation_webhook_deliveries USING btree (lead_id);


--
-- Name: index_automation_webhook_deliveries_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_webhook_deliveries_on_status ON public.automation_webhook_deliveries USING btree (status);


--
-- Name: index_automation_workflow_versions_on_automation_workflow_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_workflow_versions_on_automation_workflow_id ON public.automation_workflow_versions USING btree (automation_workflow_id);


--
-- Name: index_automation_workflow_versions_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_workflow_versions_on_created_by_id ON public.automation_workflow_versions USING btree (created_by_id);


--
-- Name: index_automation_workflow_versions_on_published_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_workflow_versions_on_published_by_id ON public.automation_workflow_versions USING btree (published_by_id);


--
-- Name: index_automation_workflow_versions_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_workflow_versions_on_tenant_id ON public.automation_workflow_versions USING btree (tenant_id);


--
-- Name: index_automation_workflows_on_active_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_workflows_on_active_version_id ON public.automation_workflows USING btree (active_version_id);


--
-- Name: index_automation_workflows_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_workflows_on_created_by_id ON public.automation_workflows USING btree (created_by_id);


--
-- Name: index_automation_workflows_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_workflows_on_status ON public.automation_workflows USING btree (status);


--
-- Name: index_automation_workflows_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_workflows_on_tenant_id ON public.automation_workflows USING btree (tenant_id);


--
-- Name: index_automation_workflows_on_tenant_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_automation_workflows_on_tenant_id_and_status ON public.automation_workflows USING btree (tenant_id, status);


--
-- Name: index_captacao_goals_on_kind_and_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_captacao_goals_on_kind_and_period ON public.captacao_goals USING btree (kind, start_date, end_date);


--
-- Name: index_captacoes_on_caracteristicas_imovel; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_captacoes_on_caracteristicas_imovel ON public.captacoes USING gin (caracteristicas_imovel);


--
-- Name: index_captacoes_on_caracteristicas_predio; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_captacoes_on_caracteristicas_predio ON public.captacoes USING gin (caracteristicas_predio);


--
-- Name: index_captacoes_on_corretor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_captacoes_on_corretor_id ON public.captacoes USING btree (corretor_id);


--
-- Name: index_captacoes_on_corretor_id_and_completed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_captacoes_on_corretor_id_and_completed ON public.captacoes USING btree (corretor_id, completed);


--
-- Name: index_captacoes_on_modalidade; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_captacoes_on_modalidade ON public.captacoes USING btree (modalidade);


--
-- Name: index_captacoes_on_property_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_captacoes_on_property_kind ON public.captacoes USING btree (property_kind);


--
-- Name: index_captacoes_on_published_on_site; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_captacoes_on_published_on_site ON public.captacoes USING btree (published_on_site);


--
-- Name: index_captacoes_on_submitted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_captacoes_on_submitted_at ON public.captacoes USING btree (submitted_at);


--
-- Name: index_check_ins_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_check_ins_on_admin_user_id ON public.check_ins USING btree (admin_user_id);


--
-- Name: index_check_ins_on_admin_user_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_check_ins_on_admin_user_id_and_status ON public.check_ins USING btree (admin_user_id, status);


--
-- Name: index_check_ins_on_fingerprint_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_check_ins_on_fingerprint_hash ON public.check_ins USING btree (fingerprint_hash);


--
-- Name: index_check_ins_on_store_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_check_ins_on_store_id ON public.check_ins USING btree (store_id);


--
-- Name: index_check_ins_on_store_id_and_checked_in_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_check_ins_on_store_id_and_checked_in_at ON public.check_ins USING btree (store_id, checked_in_at);


--
-- Name: index_check_ins_on_store_shift_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_check_ins_on_store_shift_id ON public.check_ins USING btree (store_shift_id);


--
-- Name: index_check_ins_on_suspicious; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_check_ins_on_suspicious ON public.check_ins USING btree (suspicious);


--
-- Name: index_check_ins_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_check_ins_on_tenant_id ON public.check_ins USING btree (tenant_id);


--
-- Name: index_checkin_audit_logs_on_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_checkin_audit_logs_on_action ON public.checkin_audit_logs USING btree (action);


--
-- Name: index_checkin_audit_logs_on_actor_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_checkin_audit_logs_on_actor_admin_user_id ON public.checkin_audit_logs USING btree (actor_admin_user_id);


--
-- Name: index_checkin_audit_logs_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_checkin_audit_logs_on_admin_user_id ON public.checkin_audit_logs USING btree (admin_user_id);


--
-- Name: index_checkin_audit_logs_on_admin_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_checkin_audit_logs_on_admin_user_id_and_created_at ON public.checkin_audit_logs USING btree (admin_user_id, created_at);


--
-- Name: index_checkin_audit_logs_on_check_in_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_checkin_audit_logs_on_check_in_id ON public.checkin_audit_logs USING btree (check_in_id);


--
-- Name: index_checkin_audit_logs_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_checkin_audit_logs_on_tenant_id ON public.checkin_audit_logs USING btree (tenant_id);


--
-- Name: index_client_interactions_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_client_interactions_on_admin_user_id ON public.client_interactions USING btree (admin_user_id);


--
-- Name: index_client_interactions_on_crm_contact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_client_interactions_on_crm_contact_id ON public.client_interactions USING btree (crm_contact_id);


--
-- Name: index_client_interactions_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_client_interactions_on_habitation_id ON public.client_interactions USING btree (habitation_id);


--
-- Name: index_client_interactions_on_metadata; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_client_interactions_on_metadata ON public.client_interactions USING gin (metadata);


--
-- Name: index_client_interactions_on_proprietor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_client_interactions_on_proprietor_id ON public.client_interactions USING btree (proprietor_id);


--
-- Name: index_client_interactions_on_source_table_and_source_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_client_interactions_on_source_table_and_source_key ON public.client_interactions USING btree (source_table, source_key);


--
-- Name: index_client_interactions_on_vista_client_code_and_occurred_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_client_interactions_on_vista_client_code_and_occurred_at ON public.client_interactions USING btree (vista_client_code, occurred_at);


--
-- Name: index_client_interactions_on_vista_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_client_interactions_on_vista_import_batch_id ON public.client_interactions USING btree (vista_import_batch_id);


--
-- Name: index_client_property_interests_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_client_property_interests_on_admin_user_id ON public.client_property_interests USING btree (admin_user_id);


--
-- Name: index_client_property_interests_on_criteria; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_client_property_interests_on_criteria ON public.client_property_interests USING gin (criteria);


--
-- Name: index_client_property_interests_on_crm_contact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_client_property_interests_on_crm_contact_id ON public.client_property_interests USING btree (crm_contact_id);


--
-- Name: index_client_property_interests_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_client_property_interests_on_habitation_id ON public.client_property_interests USING btree (habitation_id);


--
-- Name: index_client_property_interests_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_client_property_interests_on_lead_id ON public.client_property_interests USING btree (lead_id);


--
-- Name: index_client_property_interests_on_metadata; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_client_property_interests_on_metadata ON public.client_property_interests USING gin (metadata);


--
-- Name: index_client_property_interests_on_proprietor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_client_property_interests_on_proprietor_id ON public.client_property_interests USING btree (proprietor_id);


--
-- Name: index_client_property_interests_on_source_table_and_source_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_client_property_interests_on_source_table_and_source_key ON public.client_property_interests USING btree (source_table, source_key);


--
-- Name: index_client_property_interests_on_vista_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_client_property_interests_on_vista_import_batch_id ON public.client_property_interests USING btree (vista_import_batch_id);


--
-- Name: index_crm_appointments_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_crm_appointments_on_admin_user_id ON public.crm_appointments USING btree (admin_user_id);


--
-- Name: index_crm_appointments_on_crm_contact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_crm_appointments_on_crm_contact_id ON public.crm_appointments USING btree (crm_contact_id);


--
-- Name: index_crm_appointments_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_crm_appointments_on_habitation_id ON public.crm_appointments USING btree (habitation_id);


--
-- Name: index_crm_appointments_on_metadata; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_crm_appointments_on_metadata ON public.crm_appointments USING gin (metadata);


--
-- Name: index_crm_appointments_on_proprietor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_crm_appointments_on_proprietor_id ON public.crm_appointments USING btree (proprietor_id);


--
-- Name: index_crm_appointments_on_source_table_and_source_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_crm_appointments_on_source_table_and_source_key ON public.crm_appointments USING btree (source_table, source_key);


--
-- Name: index_crm_appointments_on_source_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_crm_appointments_on_source_updated_at ON public.crm_appointments USING btree (source_updated_at);


--
-- Name: index_crm_appointments_on_vista_client_code_and_starts_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_crm_appointments_on_vista_client_code_and_starts_at ON public.crm_appointments USING btree (vista_client_code, starts_at);


--
-- Name: index_crm_appointments_on_vista_habitation_code_and_starts_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_crm_appointments_on_vista_habitation_code_and_starts_at ON public.crm_appointments USING btree (vista_habitation_code, starts_at);


--
-- Name: index_crm_appointments_on_vista_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_crm_appointments_on_vista_import_batch_id ON public.crm_appointments USING btree (vista_import_batch_id);


--
-- Name: index_crm_contacts_on_is_owner_and_is_referenced_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_crm_contacts_on_is_owner_and_is_referenced_owner ON public.crm_contacts USING btree (is_owner, is_referenced_owner);


--
-- Name: index_crm_contacts_on_metadata; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_crm_contacts_on_metadata ON public.crm_contacts USING gin (metadata);


--
-- Name: index_crm_contacts_on_potential_value_cents; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_crm_contacts_on_potential_value_cents ON public.crm_contacts USING btree (potential_value_cents);


--
-- Name: index_crm_contacts_on_source_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_crm_contacts_on_source_status ON public.crm_contacts USING btree (source_status);


--
-- Name: index_crm_contacts_on_vista_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_crm_contacts_on_vista_code ON public.crm_contacts USING btree (vista_code);


--
-- Name: index_crm_contacts_on_vista_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_crm_contacts_on_vista_import_batch_id ON public.crm_contacts USING btree (vista_import_batch_id);


--
-- Name: index_data_export_audit_logs_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_data_export_audit_logs_on_admin_user_id ON public.data_export_audit_logs USING btree (admin_user_id);


--
-- Name: index_data_export_audit_logs_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_data_export_audit_logs_on_created_at ON public.data_export_audit_logs USING btree (created_at);


--
-- Name: index_data_export_audit_logs_on_export_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_data_export_audit_logs_on_export_type ON public.data_export_audit_logs USING btree (export_type);


--
-- Name: index_data_export_audit_logs_on_format; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_data_export_audit_logs_on_format ON public.data_export_audit_logs USING btree (format);


--
-- Name: index_data_export_audit_logs_on_resource_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_data_export_audit_logs_on_resource_name ON public.data_export_audit_logs USING btree (resource_name);


--
-- Name: index_data_export_audit_logs_on_resource_name_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_data_export_audit_logs_on_resource_name_and_created_at ON public.data_export_audit_logs USING btree (resource_name, created_at);


--
-- Name: index_data_export_audit_logs_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_data_export_audit_logs_on_tenant_id ON public.data_export_audit_logs USING btree (tenant_id);


--
-- Name: index_distribution_rule_agents_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_distribution_rule_agents_on_admin_user_id ON public.distribution_rule_agents USING btree (admin_user_id);


--
-- Name: index_distribution_rule_agents_on_distribution_rule_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_distribution_rule_agents_on_distribution_rule_id ON public.distribution_rule_agents USING btree (distribution_rule_id);


--
-- Name: index_distribution_rule_agents_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_distribution_rule_agents_on_tenant_id ON public.distribution_rule_agents USING btree (tenant_id);


--
-- Name: index_distribution_rules_on_auto_update_trigger; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_distribution_rules_on_auto_update_trigger ON public.distribution_rules USING gin (auto_update_trigger);


--
-- Name: index_distribution_rules_on_checkin_store_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_distribution_rules_on_checkin_store_id ON public.distribution_rules USING btree (checkin_store_id);


--
-- Name: index_distribution_rules_on_checkin_store_ids; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_distribution_rules_on_checkin_store_ids ON public.distribution_rules USING gin (checkin_store_ids);


--
-- Name: index_distribution_rules_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_distribution_rules_on_tenant_id ON public.distribution_rules USING btree (tenant_id);


--
-- Name: index_distribution_rules_on_tenant_id_and_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_distribution_rules_on_tenant_id_and_active ON public.distribution_rules USING btree (tenant_id, active);


--
-- Name: index_email_settings_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_email_settings_on_tenant_id ON public.email_settings USING btree (tenant_id);


--
-- Name: index_error_events_on_fingerprint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_error_events_on_fingerprint ON public.error_events USING btree (fingerprint);


--
-- Name: index_error_events_on_last_seen_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_events_on_last_seen_at ON public.error_events USING btree (last_seen_at);


--
-- Name: index_error_events_on_tenant_id_and_last_seen_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_events_on_tenant_id_and_last_seen_at ON public.error_events USING btree (tenant_id, last_seen_at);


--
-- Name: index_featured_properties_view_on_categoria; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_featured_properties_view_on_categoria ON public.featured_properties_view USING btree (categoria);


--
-- Name: index_featured_properties_view_on_cidade; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_featured_properties_view_on_cidade ON public.featured_properties_view USING btree (cidade);


--
-- Name: index_featured_properties_view_on_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_featured_properties_view_on_id ON public.featured_properties_view USING btree (id);


--
-- Name: index_footer_links_on_footer_setting_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_footer_links_on_footer_setting_id ON public.footer_links USING btree (footer_setting_id);


--
-- Name: index_footer_social_links_on_footer_setting_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_footer_social_links_on_footer_setting_id ON public.footer_social_links USING btree (footer_setting_id);


--
-- Name: index_footer_stores_on_footer_setting_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_footer_stores_on_footer_setting_id ON public.footer_stores USING btree (footer_setting_id);


--
-- Name: index_friendly_id_slugs_on_slug_and_sluggable_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_friendly_id_slugs_on_slug_and_sluggable_type ON public.friendly_id_slugs USING btree (slug, sluggable_type);


--
-- Name: index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope ON public.friendly_id_slugs USING btree (slug, sluggable_type, scope);


--
-- Name: index_friendly_id_slugs_on_sluggable_type_and_sluggable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_friendly_id_slugs_on_sluggable_type_and_sluggable_id ON public.friendly_id_slugs USING btree (sluggable_type, sluggable_id);


--
-- Name: index_google_calendar_integration_settings_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_google_calendar_integration_settings_on_tenant_id ON public.google_calendar_integration_settings USING btree (tenant_id);


--
-- Name: index_google_maps_integration_settings_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_google_maps_integration_settings_on_tenant_id ON public.google_maps_integration_settings USING btree (tenant_id);


--
-- Name: index_habitation_audit_logs_on_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_audit_logs_on_action ON public.habitation_audit_logs USING btree (action);


--
-- Name: index_habitation_audit_logs_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_audit_logs_on_admin_user_id ON public.habitation_audit_logs USING btree (admin_user_id);


--
-- Name: index_habitation_audit_logs_on_admin_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_audit_logs_on_admin_user_id_and_created_at ON public.habitation_audit_logs USING btree (admin_user_id, created_at);


--
-- Name: index_habitation_audit_logs_on_changed_fields; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_audit_logs_on_changed_fields ON public.habitation_audit_logs USING gin (changed_fields);


--
-- Name: index_habitation_audit_logs_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_audit_logs_on_habitation_id ON public.habitation_audit_logs USING btree (habitation_id);


--
-- Name: index_habitation_audit_logs_on_habitation_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_audit_logs_on_habitation_id_and_created_at ON public.habitation_audit_logs USING btree (habitation_id, created_at);


--
-- Name: index_habitation_audit_logs_on_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_audit_logs_on_source ON public.habitation_audit_logs USING btree (source);


--
-- Name: index_habitation_audit_logs_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_audit_logs_on_tenant_id ON public.habitation_audit_logs USING btree (tenant_id);


--
-- Name: index_habitation_broker_assignments_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_broker_assignments_on_admin_user_id ON public.habitation_broker_assignments USING btree (admin_user_id);


--
-- Name: index_habitation_broker_assignments_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_broker_assignments_on_habitation_id ON public.habitation_broker_assignments USING btree (habitation_id);


--
-- Name: index_habitation_broker_assignments_on_vista_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_broker_assignments_on_vista_import_batch_id ON public.habitation_broker_assignments USING btree (vista_import_batch_id);


--
-- Name: index_habitation_exports_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_exports_on_admin_user_id ON public.habitation_exports USING btree (admin_user_id);


--
-- Name: index_habitation_exports_on_admin_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_exports_on_admin_user_id_and_created_at ON public.habitation_exports USING btree (admin_user_id, created_at);


--
-- Name: index_habitation_exports_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_exports_on_tenant_id ON public.habitation_exports USING btree (tenant_id);


--
-- Name: index_habitation_interactions_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_interactions_on_admin_user_id ON public.habitation_interactions USING btree (admin_user_id);


--
-- Name: index_habitation_interactions_on_crm_contact_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_interactions_on_crm_contact_id ON public.habitation_interactions USING btree (crm_contact_id);


--
-- Name: index_habitation_interactions_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_interactions_on_habitation_id ON public.habitation_interactions USING btree (habitation_id);


--
-- Name: index_habitation_interactions_on_proprietor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_interactions_on_proprietor_id ON public.habitation_interactions USING btree (proprietor_id);


--
-- Name: index_habitation_interactions_on_source_table_and_source_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_habitation_interactions_on_source_table_and_source_key ON public.habitation_interactions USING btree (source_table, source_key);


--
-- Name: index_habitation_interactions_on_vista_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_interactions_on_vista_import_batch_id ON public.habitation_interactions USING btree (vista_import_batch_id);


--
-- Name: index_habitation_photo_shares_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_photo_shares_on_admin_user_id ON public.habitation_photo_shares USING btree (admin_user_id);


--
-- Name: index_habitation_photo_shares_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_photo_shares_on_habitation_id ON public.habitation_photo_shares USING btree (habitation_id);


--
-- Name: index_habitation_photo_shares_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_habitation_photo_shares_on_token ON public.habitation_photo_shares USING btree (token);


--
-- Name: index_habitation_share_links_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_share_links_on_admin_user_id ON public.habitation_share_links USING btree (admin_user_id);


--
-- Name: index_habitation_share_links_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitation_share_links_on_habitation_id ON public.habitation_share_links USING btree (habitation_id);


--
-- Name: index_habitation_share_links_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_habitation_share_links_on_token ON public.habitation_share_links USING btree (token);


--
-- Name: index_habitations_on_aceita_permuta_flag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_aceita_permuta_flag ON public.habitations USING btree (aceita_permuta_flag);


--
-- Name: index_habitations_on_admin_reviewed_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_admin_reviewed_by_id ON public.habitations USING btree (admin_reviewed_by_id);


--
-- Name: index_habitations_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_admin_user_id ON public.habitations USING btree (admin_user_id);


--
-- Name: index_habitations_on_area_total_m2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_area_total_m2 ON public.habitations USING btree (area_total_m2);


--
-- Name: index_habitations_on_caracteristicas; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_caracteristicas ON public.habitations USING gin (caracteristicas);


--
-- Name: index_habitations_on_centro_flag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_centro_flag ON public.habitations USING btree (centro_flag);


--
-- Name: index_habitations_on_codigo_empreendimento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_codigo_empreendimento ON public.habitations USING btree (codigo_empreendimento);


--
-- Name: index_habitations_on_constructor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_constructor_id ON public.habitations USING btree (constructor_id);


--
-- Name: index_habitations_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_created_at ON public.habitations USING btree (created_at);


--
-- Name: index_habitations_on_data_atualizacao_crm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_data_atualizacao_crm ON public.habitations USING btree (data_atualizacao_crm);


--
-- Name: index_habitations_on_destaque_localizacao; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_destaque_localizacao ON public.habitations USING gin (destaque_localizacao);


--
-- Name: index_habitations_on_destaque_web_flag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_destaque_web_flag ON public.habitations USING btree (destaque_web_flag);


--
-- Name: index_habitations_on_dormitorios_qtd; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_dormitorios_qtd ON public.habitations USING btree (dormitorios_qtd);


--
-- Name: index_habitations_on_frente_mar_avenida_atlantica_flag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_frente_mar_avenida_atlantica_flag ON public.habitations USING btree (frente_mar_avenida_atlantica_flag);


--
-- Name: index_habitations_on_home_corporate_flag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_home_corporate_flag ON public.habitations USING btree (home_corporate_flag);


--
-- Name: index_habitations_on_infra_estrutura; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_infra_estrutura ON public.habitations USING gin (infra_estrutura);


--
-- Name: index_habitations_on_intake_group_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_intake_group_uuid ON public.habitations USING btree (intake_group_uuid);


--
-- Name: index_habitations_on_intake_modalidade; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_intake_modalidade ON public.habitations USING btree (intake_modalidade);


--
-- Name: index_habitations_on_intake_origin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_intake_origin ON public.habitations USING btree (intake_origin);


--
-- Name: index_habitations_on_intake_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_intake_status ON public.habitations USING btree (intake_status);


--
-- Name: index_habitations_on_intake_step; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_intake_step ON public.habitations USING btree (intake_step);


--
-- Name: index_habitations_on_key_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_key_location ON public.habitations USING btree (key_location);


--
-- Name: index_habitations_on_lancamento_flag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_lancamento_flag ON public.habitations USING btree (lancamento_flag);


--
-- Name: index_habitations_on_lavabo_flag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_lavabo_flag ON public.habitations USING btree (lavabo_flag);


--
-- Name: index_habitations_on_photo_calendar_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_photo_calendar_event_id ON public.habitations USING btree (photo_calendar_event_id);


--
-- Name: index_habitations_on_pictures; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_pictures ON public.habitations USING gin (pictures);


--
-- Name: index_habitations_on_piscina_flag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_piscina_flag ON public.habitations USING btree (piscina_flag);


--
-- Name: index_habitations_on_praia_brava_flag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_praia_brava_flag ON public.habitations USING btree (praia_brava_flag);


--
-- Name: index_habitations_on_proprietor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_proprietor_id ON public.habitations USING btree (proprietor_id);


--
-- Name: index_habitations_on_publicar_casa_mineira; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_publicar_casa_mineira ON public.habitations USING btree (publicar_casa_mineira);


--
-- Name: index_habitations_on_publicar_chaves_na_mao; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_publicar_chaves_na_mao ON public.habitations USING btree (publicar_chaves_na_mao);


--
-- Name: index_habitations_on_publicar_imovelweb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_publicar_imovelweb ON public.habitations USING btree (publicar_imovelweb);


--
-- Name: index_habitations_on_publicar_imovelweb_2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_publicar_imovelweb_2 ON public.habitations USING btree (publicar_imovelweb_2);


--
-- Name: index_habitations_on_publicar_lais_ai; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_publicar_lais_ai ON public.habitations USING btree (publicar_lais_ai);


--
-- Name: index_habitations_on_publicar_loft; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_publicar_loft ON public.habitations USING btree (publicar_loft);


--
-- Name: index_habitations_on_publicar_netimoveis_2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_publicar_netimoveis_2 ON public.habitations USING btree (publicar_netimoveis_2);


--
-- Name: index_habitations_on_publicar_viva_real_vrsync; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_publicar_viva_real_vrsync ON public.habitations USING btree (publicar_viva_real_vrsync);


--
-- Name: index_habitations_on_publicar_zapimoveis; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_publicar_zapimoveis ON public.habitations USING btree (publicar_zapimoveis);


--
-- Name: index_habitations_on_quadra_mar_flag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_quadra_mar_flag ON public.habitations USING btree (quadra_mar_flag);


--
-- Name: index_habitations_on_salute_rental_management_flag; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_salute_rental_management_flag ON public.habitations USING btree (salute_rental_management_flag);


--
-- Name: index_habitations_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_habitations_on_slug ON public.habitations USING btree (slug);


--
-- Name: index_habitations_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_tenant_id ON public.habitations USING btree (tenant_id);


--
-- Name: index_habitations_on_tenant_id_and_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_tenant_id_and_admin_user_id ON public.habitations USING btree (tenant_id, admin_user_id);


--
-- Name: index_habitations_on_tenant_id_and_codigo; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_habitations_on_tenant_id_and_codigo ON public.habitations USING btree (tenant_id, codigo);


--
-- Name: index_habitations_on_tenant_id_and_codigo_dwv_unique_when_dwv; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_habitations_on_tenant_id_and_codigo_dwv_unique_when_dwv ON public.habitations USING btree (tenant_id, codigo_dwv) WHERE (((imovel_dwv)::text = 'Sim'::text) AND (codigo_dwv IS NOT NULL) AND ((codigo_dwv)::text <> ''::text));


--
-- Name: index_habitations_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_updated_at ON public.habitations USING btree (updated_at);


--
-- Name: index_habitations_on_vagas_qtd; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_vagas_qtd ON public.habitations USING btree (vagas_qtd);


--
-- Name: index_habitations_on_valor_locacao_cents; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_valor_locacao_cents ON public.habitations USING btree (valor_locacao_cents);


--
-- Name: index_habitations_on_valor_venda_cents; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_valor_venda_cents ON public.habitations USING btree (valor_venda_cents);


--
-- Name: index_habitations_on_vista_codigo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_vista_codigo ON public.habitations USING btree (vista_codigo);


--
-- Name: index_habitations_on_vista_imo_codigo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_vista_imo_codigo ON public.habitations USING btree (vista_imo_codigo);


--
-- Name: index_habitations_on_vista_imo_placa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_vista_imo_placa ON public.habitations USING btree (vista_imo_placa);


--
-- Name: index_habitations_on_vista_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_vista_import_batch_id ON public.habitations USING btree (vista_import_batch_id);


--
-- Name: index_habitations_on_vista_referencia_externa; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_habitations_on_vista_referencia_externa ON public.habitations USING btree (vista_referencia_externa);


--
-- Name: index_home_hero_slides_on_home_setting_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_home_hero_slides_on_home_setting_id ON public.home_hero_slides USING btree (home_setting_id);


--
-- Name: index_home_hero_slides_on_home_setting_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_home_hero_slides_on_home_setting_id_and_position ON public.home_hero_slides USING btree (home_setting_id, "position");


--
-- Name: index_home_section_items_on_home_section_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_home_section_items_on_home_section_id ON public.home_section_items USING btree (home_section_id);


--
-- Name: index_inbound_webhook_tokens_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inbound_webhook_tokens_on_admin_user_id ON public.inbound_webhook_tokens USING btree (admin_user_id);


--
-- Name: index_inbound_webhook_tokens_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inbound_webhook_tokens_on_token ON public.inbound_webhook_tokens USING btree (token);


--
-- Name: index_lead_activities_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_activities_on_lead_id ON public.lead_activities USING btree (lead_id);


--
-- Name: index_lead_activities_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_activities_on_tenant_id ON public.lead_activities USING btree (tenant_id);


--
-- Name: index_lead_audit_logs_on_action; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_audit_logs_on_action ON public.lead_audit_logs USING btree (action);


--
-- Name: index_lead_audit_logs_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_audit_logs_on_admin_user_id ON public.lead_audit_logs USING btree (admin_user_id);


--
-- Name: index_lead_audit_logs_on_admin_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_audit_logs_on_admin_user_id_and_created_at ON public.lead_audit_logs USING btree (admin_user_id, created_at);


--
-- Name: index_lead_audit_logs_on_changed_fields; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_audit_logs_on_changed_fields ON public.lead_audit_logs USING gin (changed_fields);


--
-- Name: index_lead_audit_logs_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_audit_logs_on_lead_id ON public.lead_audit_logs USING btree (lead_id);


--
-- Name: index_lead_audit_logs_on_lead_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_audit_logs_on_lead_id_and_created_at ON public.lead_audit_logs USING btree (lead_id, created_at);


--
-- Name: index_lead_audit_logs_on_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_audit_logs_on_source ON public.lead_audit_logs USING btree (source);


--
-- Name: index_lead_audit_logs_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_audit_logs_on_tenant_id ON public.lead_audit_logs USING btree (tenant_id);


--
-- Name: index_lead_labelings_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_labelings_on_lead_id ON public.lead_labelings USING btree (lead_id);


--
-- Name: index_lead_labelings_on_lead_id_and_lead_label_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_lead_labelings_on_lead_id_and_lead_label_id ON public.lead_labelings USING btree (lead_id, lead_label_id);


--
-- Name: index_lead_labelings_on_lead_label_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_labelings_on_lead_label_id ON public.lead_labelings USING btree (lead_label_id);


--
-- Name: index_lead_labelings_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_labelings_on_tenant_id ON public.lead_labelings USING btree (tenant_id);


--
-- Name: index_lead_labels_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_labels_on_admin_user_id ON public.lead_labels USING btree (admin_user_id);


--
-- Name: index_lead_labels_on_admin_user_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_lead_labels_on_admin_user_id_and_name ON public.lead_labels USING btree (admin_user_id, name);


--
-- Name: index_lead_labels_on_admin_user_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_labels_on_admin_user_id_and_position ON public.lead_labels USING btree (admin_user_id, "position");


--
-- Name: index_lead_labels_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_labels_on_tenant_id ON public.lead_labels USING btree (tenant_id);


--
-- Name: index_lead_property_interests_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_property_interests_on_habitation_id ON public.lead_property_interests USING btree (habitation_id);


--
-- Name: index_lead_property_interests_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_property_interests_on_lead_id ON public.lead_property_interests USING btree (lead_id);


--
-- Name: index_lead_property_interests_on_lead_id_and_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_lead_property_interests_on_lead_id_and_habitation_id ON public.lead_property_interests USING btree (lead_id, habitation_id);


--
-- Name: index_lead_property_interests_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lead_property_interests_on_tenant_id ON public.lead_property_interests USING btree (tenant_id);


--
-- Name: index_leads_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_admin_user_id ON public.leads USING btree (admin_user_id);


--
-- Name: index_leads_on_bsuid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_bsuid ON public.leads USING btree (business_scoped_user_id) WHERE (business_scoped_user_id IS NOT NULL);


--
-- Name: index_leads_on_client_c2s_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_client_c2s_id ON public.leads USING btree (client_c2s_id);


--
-- Name: index_leads_on_distribution_rule_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_distribution_rule_id ON public.leads USING btree (distribution_rule_id);


--
-- Name: index_leads_on_origin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_origin ON public.leads USING btree (origin);


--
-- Name: index_leads_on_share_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_share_token ON public.leads USING btree (share_token);


--
-- Name: index_leads_on_shared_by_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_shared_by_admin_user_id ON public.leads USING btree (shared_by_admin_user_id);


--
-- Name: index_leads_on_status_waiting_acceptance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_status_waiting_acceptance ON public.leads USING btree (status) WHERE ((status)::text = 'Aguardando Aceite'::text);


--
-- Name: index_leads_on_tags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_tags ON public.leads USING gin (tags);


--
-- Name: index_leads_on_tenant_and_client_email_lower; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_tenant_and_client_email_lower ON public.leads USING btree (tenant_id, lower((COALESCE(client_email, ''::character varying))::text));


--
-- Name: index_leads_on_tenant_and_client_phone_digits; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_tenant_and_client_phone_digits ON public.leads USING btree (tenant_id, regexp_replace((COALESCE(client_phone, ''::character varying))::text, '\D'::text, ''::text, 'g'::text));


--
-- Name: index_leads_on_tenant_and_email_lower; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_tenant_and_email_lower ON public.leads USING btree (tenant_id, lower((COALESCE(email, ''::character varying))::text));


--
-- Name: index_leads_on_tenant_and_phone_digits; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_tenant_and_phone_digits ON public.leads USING btree (tenant_id, regexp_replace((COALESCE(phone, ''::character varying))::text, '\D'::text, ''::text, 'g'::text));


--
-- Name: index_leads_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_tenant_id ON public.leads USING btree (tenant_id);


--
-- Name: index_leads_on_tenant_id_and_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_tenant_id_and_admin_user_id ON public.leads USING btree (tenant_id, admin_user_id);


--
-- Name: index_leads_on_tenant_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_tenant_id_and_created_at ON public.leads USING btree (tenant_id, created_at);


--
-- Name: index_leads_on_tenant_id_and_property_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_tenant_id_and_property_id ON public.leads USING btree (tenant_id, property_id);


--
-- Name: index_leads_on_tenant_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_tenant_id_and_status ON public.leads USING btree (tenant_id, status);


--
-- Name: index_leads_on_tenant_meta_leadgen; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_leads_on_tenant_meta_leadgen ON public.leads USING btree (tenant_id, ((other_information ->> 'meta_leadgen_id'::text))) WHERE ((other_information ->> 'meta_leadgen_id'::text) IS NOT NULL);


--
-- Name: index_leads_on_vista_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_vista_import_batch_id ON public.leads USING btree (vista_import_batch_id);


--
-- Name: index_leads_on_vista_payload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_vista_payload ON public.leads USING gin (vista_payload);


--
-- Name: index_location_pings_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_location_pings_on_admin_user_id ON public.location_pings USING btree (admin_user_id);


--
-- Name: index_location_pings_on_admin_user_id_and_recorded_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_location_pings_on_admin_user_id_and_recorded_at ON public.location_pings USING btree (admin_user_id, recorded_at);


--
-- Name: index_location_pings_on_check_in_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_location_pings_on_check_in_id ON public.location_pings USING btree (check_in_id);


--
-- Name: index_location_pings_on_check_in_id_and_recorded_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_location_pings_on_check_in_id_and_recorded_at ON public.location_pings USING btree (check_in_id, recorded_at);


--
-- Name: index_manual_checkin_requests_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_manual_checkin_requests_on_admin_user_id ON public.manual_checkin_requests USING btree (admin_user_id);


--
-- Name: index_manual_checkin_requests_on_approved_check_in_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_manual_checkin_requests_on_approved_check_in_id ON public.manual_checkin_requests USING btree (approved_check_in_id);


--
-- Name: index_manual_checkin_requests_on_reviewed_by_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_manual_checkin_requests_on_reviewed_by_admin_user_id ON public.manual_checkin_requests USING btree (reviewed_by_admin_user_id);


--
-- Name: index_manual_checkin_requests_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_manual_checkin_requests_on_status ON public.manual_checkin_requests USING btree (status);


--
-- Name: index_manual_checkin_requests_on_store_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_manual_checkin_requests_on_store_id ON public.manual_checkin_requests USING btree (store_id);


--
-- Name: index_manual_checkin_requests_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_manual_checkin_requests_on_tenant_id ON public.manual_checkin_requests USING btree (tenant_id);


--
-- Name: index_marketing_campaigns_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_marketing_campaigns_on_admin_user_id ON public.marketing_campaigns USING btree (admin_user_id);


--
-- Name: index_marketing_campaigns_on_channel; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_marketing_campaigns_on_channel ON public.marketing_campaigns USING btree (channel);


--
-- Name: index_marketing_campaigns_on_last_clicked_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_marketing_campaigns_on_last_clicked_at ON public.marketing_campaigns USING btree (last_clicked_at);


--
-- Name: index_marketing_campaigns_on_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_marketing_campaigns_on_priority ON public.marketing_campaigns USING btree (priority);


--
-- Name: index_marketing_campaigns_on_seo_setting_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_marketing_campaigns_on_seo_setting_id ON public.marketing_campaigns USING btree (seo_setting_id);


--
-- Name: index_marketing_campaigns_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_marketing_campaigns_on_slug ON public.marketing_campaigns USING btree (slug);


--
-- Name: index_marketing_campaigns_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_marketing_campaigns_on_status ON public.marketing_campaigns USING btree (status);


--
-- Name: index_marketing_campaigns_on_utm_campaign; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_marketing_campaigns_on_utm_campaign ON public.marketing_campaigns USING btree (utm_campaign);


--
-- Name: index_meta_facebook_pages_on_user_meta_integration_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_meta_facebook_pages_on_user_meta_integration_id ON public.meta_facebook_pages USING btree (user_meta_integration_id);


--
-- Name: index_meta_lead_forms_on_meta_facebook_page_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_meta_lead_forms_on_meta_facebook_page_id ON public.meta_lead_forms USING btree (meta_facebook_page_id);


--
-- Name: index_notification_template_settings_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notification_template_settings_on_tenant_id ON public.notification_template_settings USING btree (tenant_id);


--
-- Name: index_notification_template_settings_on_tenant_id_and_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notification_template_settings_on_tenant_id_and_active ON public.notification_template_settings USING btree (tenant_id, active);


--
-- Name: index_notification_template_settings_on_whatsapp_template_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notification_template_settings_on_whatsapp_template_id ON public.notification_template_settings USING btree (whatsapp_template_id);


--
-- Name: index_photography_schedule_blocks_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_photography_schedule_blocks_on_created_by_id ON public.photography_schedule_blocks USING btree (created_by_id);


--
-- Name: index_photography_schedule_blocks_on_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_photography_schedule_blocks_on_date ON public.photography_schedule_blocks USING btree (date);


--
-- Name: index_portal_integration_events_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_portal_integration_events_on_habitation_id ON public.portal_integration_events USING btree (habitation_id);


--
-- Name: index_portal_integration_events_on_portal_and_habitation_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_portal_integration_events_on_portal_and_habitation_code ON public.portal_integration_events USING btree (portal, habitation_code);


--
-- Name: index_portal_integration_events_on_portal_and_received_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_portal_integration_events_on_portal_and_received_at ON public.portal_integration_events USING btree (portal, received_at);


--
-- Name: index_portal_integration_events_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_portal_integration_events_on_tenant_id ON public.portal_integration_events USING btree (tenant_id);


--
-- Name: index_portal_integrations_on_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_portal_integrations_on_enabled ON public.portal_integrations USING btree (enabled);


--
-- Name: index_portal_integrations_on_feed_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_portal_integrations_on_feed_token ON public.portal_integrations USING btree (feed_token);


--
-- Name: index_portal_integrations_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_portal_integrations_on_tenant_id ON public.portal_integrations USING btree (tenant_id);


--
-- Name: index_portal_listing_states_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_portal_listing_states_on_habitation_id ON public.portal_listing_states USING btree (habitation_id);


--
-- Name: index_portal_listing_states_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_portal_listing_states_on_tenant_id ON public.portal_listing_states USING btree (tenant_id);


--
-- Name: index_presentation_cards_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_presentation_cards_on_admin_user_id ON public.presentation_cards USING btree (admin_user_id);


--
-- Name: index_presentation_cards_on_admin_user_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_presentation_cards_on_admin_user_id_and_position ON public.presentation_cards USING btree (admin_user_id, "position");


--
-- Name: index_presentation_cards_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_presentation_cards_on_tenant_id ON public.presentation_cards USING btree (tenant_id);


--
-- Name: index_profiles_on_id_and_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_profiles_on_id_and_tenant_id ON public.profiles USING btree (id, tenant_id);


--
-- Name: index_profiles_on_tenant_and_vertical_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_profiles_on_tenant_and_vertical_position ON public.profiles USING btree (tenant_id, "position") WHERE ((axis)::text = 'vertical'::text);


--
-- Name: index_profiles_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_profiles_on_tenant_id ON public.profiles USING btree (tenant_id);


--
-- Name: index_profiles_on_tenant_id_and_axis_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_profiles_on_tenant_id_and_axis_and_position ON public.profiles USING btree (tenant_id, axis, "position");


--
-- Name: index_profiles_on_tenant_id_and_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_profiles_on_tenant_id_and_key ON public.profiles USING btree (tenant_id, key) WHERE (key IS NOT NULL);


--
-- Name: index_profiles_on_tenant_id_and_vertical_profile_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_profiles_on_tenant_id_and_vertical_profile_id_and_name ON public.profiles USING btree (tenant_id, vertical_profile_id, name) WHERE ((axis)::text = 'horizontal'::text);


--
-- Name: index_profiles_on_vertical_profile_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_profiles_on_vertical_profile_id ON public.profiles USING btree (vertical_profile_id);


--
-- Name: index_property_pages_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_property_pages_on_slug ON public.property_pages USING btree (slug);


--
-- Name: index_property_settings_on_broker_capture_layer_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_property_settings_on_broker_capture_layer_enabled ON public.property_settings USING btree (broker_capture_layer_enabled);


--
-- Name: index_property_settings_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_property_settings_on_tenant_id ON public.property_settings USING btree (tenant_id);


--
-- Name: index_proposals_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proposals_on_admin_user_id ON public.proposals USING btree (admin_user_id);


--
-- Name: index_proposals_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proposals_on_habitation_id ON public.proposals USING btree (habitation_id);


--
-- Name: index_proposals_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proposals_on_lead_id ON public.proposals USING btree (lead_id);


--
-- Name: index_proposals_on_lead_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proposals_on_lead_id_and_status ON public.proposals USING btree (lead_id, status);


--
-- Name: index_proposals_on_public_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_proposals_on_public_token ON public.proposals USING btree (public_token);


--
-- Name: index_proprietors_on_cpf_cnpj; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proprietors_on_cpf_cnpj ON public.proprietors USING btree (cpf_cnpj);


--
-- Name: index_proprietors_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proprietors_on_email ON public.proprietors USING btree (email);


--
-- Name: index_proprietors_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proprietors_on_name ON public.proprietors USING btree (name);


--
-- Name: index_proprietors_on_source_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proprietors_on_source_status ON public.proprietors USING btree (source_status);


--
-- Name: index_proprietors_on_spouse_cpf_cnpj; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proprietors_on_spouse_cpf_cnpj ON public.proprietors USING btree (spouse_cpf_cnpj);


--
-- Name: index_proprietors_on_spouse_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proprietors_on_spouse_email ON public.proprietors USING btree (spouse_email);


--
-- Name: index_proprietors_on_spouse_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proprietors_on_spouse_name ON public.proprietors USING btree (spouse_name);


--
-- Name: index_proprietors_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proprietors_on_tenant_id ON public.proprietors USING btree (tenant_id);


--
-- Name: index_proprietors_on_tenant_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proprietors_on_tenant_id_and_name ON public.proprietors USING btree (tenant_id, name);


--
-- Name: index_proprietors_on_vista_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proprietors_on_vista_code ON public.proprietors USING btree (vista_code);


--
-- Name: index_proprietors_on_vista_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proprietors_on_vista_import_batch_id ON public.proprietors USING btree (vista_import_batch_id);


--
-- Name: index_proprietors_on_vista_payload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_proprietors_on_vista_payload ON public.proprietors USING gin (vista_payload);


--
-- Name: index_public_navigation_events_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_public_navigation_events_on_habitation_id ON public.public_navigation_events USING btree (habitation_id);


--
-- Name: index_public_navigation_events_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_public_navigation_events_on_lead_id ON public.public_navigation_events USING btree (lead_id);


--
-- Name: index_public_navigation_events_on_public_navigation_session_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_public_navigation_events_on_public_navigation_session_id ON public.public_navigation_events USING btree (public_navigation_session_id);


--
-- Name: index_public_navigation_sessions_on_last_seen_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_public_navigation_sessions_on_last_seen_at ON public.public_navigation_sessions USING btree (last_seen_at);


--
-- Name: index_public_navigation_sessions_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_public_navigation_sessions_on_lead_id ON public.public_navigation_sessions USING btree (lead_id);


--
-- Name: index_public_navigation_sessions_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_public_navigation_sessions_on_token ON public.public_navigation_sessions USING btree (token);


--
-- Name: index_push_delivery_events_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_push_delivery_events_on_admin_user_id ON public.push_delivery_events USING btree (admin_user_id);


--
-- Name: index_push_delivery_events_on_admin_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_push_delivery_events_on_admin_user_id_and_created_at ON public.push_delivery_events USING btree (admin_user_id, created_at);


--
-- Name: index_push_delivery_events_on_endpoint_sha256; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_push_delivery_events_on_endpoint_sha256 ON public.push_delivery_events USING btree (endpoint_sha256);


--
-- Name: index_push_delivery_events_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_push_delivery_events_on_lead_id ON public.push_delivery_events USING btree (lead_id);


--
-- Name: index_push_delivery_events_on_lead_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_push_delivery_events_on_lead_id_and_created_at ON public.push_delivery_events USING btree (lead_id, created_at);


--
-- Name: index_push_delivery_events_on_push_subscription_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_push_delivery_events_on_push_subscription_id ON public.push_delivery_events USING btree (push_subscription_id);


--
-- Name: index_push_delivery_events_on_tag_and_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_push_delivery_events_on_tag_and_event_type ON public.push_delivery_events USING btree (tag, event_type);


--
-- Name: index_push_subscriptions_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_push_subscriptions_on_active ON public.push_subscriptions USING btree (active);


--
-- Name: index_push_subscriptions_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_push_subscriptions_on_admin_user_id ON public.push_subscriptions USING btree (admin_user_id);


--
-- Name: index_push_subscriptions_on_admin_user_id_and_endpoint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_push_subscriptions_on_admin_user_id_and_endpoint ON public.push_subscriptions USING btree (admin_user_id, endpoint);


--
-- Name: index_secure_links_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_secure_links_on_lead_id ON public.secure_links USING btree (lead_id);


--
-- Name: index_secure_links_on_lead_id_and_action_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_secure_links_on_lead_id_and_action_type ON public.secure_links USING btree (lead_id, action_type);


--
-- Name: index_secure_links_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_secure_links_on_token ON public.secure_links USING btree (token);


--
-- Name: index_seo_change_logs_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_change_logs_on_admin_user_id ON public.seo_change_logs USING btree (admin_user_id);


--
-- Name: index_seo_change_logs_on_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_change_logs_on_event_type ON public.seo_change_logs USING btree (event_type);


--
-- Name: index_seo_change_logs_on_seo_setting_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_change_logs_on_seo_setting_id ON public.seo_change_logs USING btree (seo_setting_id);


--
-- Name: index_seo_change_logs_on_seo_setting_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_change_logs_on_seo_setting_id_and_created_at ON public.seo_change_logs USING btree (seo_setting_id, created_at);


--
-- Name: index_seo_conversion_events_on_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_conversion_events_on_event_type ON public.seo_conversion_events USING btree (event_type);


--
-- Name: index_seo_conversion_events_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_conversion_events_on_habitation_id ON public.seo_conversion_events USING btree (habitation_id);


--
-- Name: index_seo_conversion_events_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_conversion_events_on_lead_id ON public.seo_conversion_events USING btree (lead_id);


--
-- Name: index_seo_conversion_events_on_marketing_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_conversion_events_on_marketing_campaign_id ON public.seo_conversion_events USING btree (marketing_campaign_id);


--
-- Name: index_seo_conversion_events_on_occurred_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_conversion_events_on_occurred_at ON public.seo_conversion_events USING btree (occurred_at);


--
-- Name: index_seo_conversion_events_on_seo_setting_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_conversion_events_on_seo_setting_id ON public.seo_conversion_events USING btree (seo_setting_id);


--
-- Name: index_seo_conversion_events_on_visitor_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_conversion_events_on_visitor_hash ON public.seo_conversion_events USING btree (visitor_hash);


--
-- Name: index_seo_conversions_on_page_type_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_conversions_on_page_type_time ON public.seo_conversion_events USING btree (seo_setting_id, event_type, occurred_at);


--
-- Name: index_seo_focus_keywords_on_seo_setting_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_focus_keywords_on_seo_setting_id ON public.seo_focus_keywords USING btree (seo_setting_id);


--
-- Name: index_seo_focus_keywords_on_seo_setting_id_and_keyword; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_seo_focus_keywords_on_seo_setting_id_and_keyword ON public.seo_focus_keywords USING btree (seo_setting_id, keyword);


--
-- Name: index_seo_focus_keywords_on_seo_setting_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_focus_keywords_on_seo_setting_id_and_position ON public.seo_focus_keywords USING btree (seo_setting_id, "position");


--
-- Name: index_seo_page_visits_on_page_visitor_day; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_seo_page_visits_on_page_visitor_day ON public.seo_page_visits USING btree (seo_setting_id, visitor_hash, visited_on);


--
-- Name: index_seo_page_visits_on_seo_setting_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_page_visits_on_seo_setting_id ON public.seo_page_visits USING btree (seo_setting_id);


--
-- Name: index_seo_page_visits_on_visited_on_and_seo_setting_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_page_visits_on_visited_on_and_seo_setting_id ON public.seo_page_visits USING btree (visited_on, seo_setting_id);


--
-- Name: index_seo_page_visits_on_visitor_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_page_visits_on_visitor_hash ON public.seo_page_visits USING btree (visitor_hash);


--
-- Name: index_seo_redirects_on_active_and_from_path; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_redirects_on_active_and_from_path ON public.seo_redirects USING btree (active, from_path);


--
-- Name: index_seo_redirects_on_created_by_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_redirects_on_created_by_admin_user_id ON public.seo_redirects USING btree (created_by_admin_user_id);


--
-- Name: index_seo_redirects_on_from_path; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_seo_redirects_on_from_path ON public.seo_redirects USING btree (from_path);


--
-- Name: index_seo_settings_on_canonical_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_seo_settings_on_canonical_key ON public.seo_settings USING btree (canonical_key);


--
-- Name: index_seo_settings_on_last_accessed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_settings_on_last_accessed_at ON public.seo_settings USING btree (last_accessed_at);


--
-- Name: index_seo_settings_on_page_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_settings_on_page_type ON public.seo_settings USING btree (page_type);


--
-- Name: index_seo_settings_on_seo_score; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seo_settings_on_seo_score ON public.seo_settings USING btree (seo_score);


--
-- Name: index_settings_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_settings_on_tenant_id ON public.settings USING btree (tenant_id);


--
-- Name: index_solid_queue_blocked_executions_for_maintenance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_blocked_executions_for_maintenance ON public.solid_queue_blocked_executions USING btree (expires_at, concurrency_key);


--
-- Name: index_solid_queue_blocked_executions_for_release; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_blocked_executions_for_release ON public.solid_queue_blocked_executions USING btree (concurrency_key, priority, job_id);


--
-- Name: index_solid_queue_blocked_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_blocked_executions_on_job_id ON public.solid_queue_blocked_executions USING btree (job_id);


--
-- Name: index_solid_queue_claimed_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_claimed_executions_on_job_id ON public.solid_queue_claimed_executions USING btree (job_id);


--
-- Name: index_solid_queue_claimed_executions_on_process_id_and_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_claimed_executions_on_process_id_and_job_id ON public.solid_queue_claimed_executions USING btree (process_id, job_id);


--
-- Name: index_solid_queue_dispatch_all; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_dispatch_all ON public.solid_queue_scheduled_executions USING btree (scheduled_at, priority, job_id);


--
-- Name: index_solid_queue_failed_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_failed_executions_on_job_id ON public.solid_queue_failed_executions USING btree (job_id);


--
-- Name: index_solid_queue_jobs_for_alerting; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_for_alerting ON public.solid_queue_jobs USING btree (scheduled_at, finished_at);


--
-- Name: index_solid_queue_jobs_for_filtering; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_for_filtering ON public.solid_queue_jobs USING btree (queue_name, finished_at);


--
-- Name: index_solid_queue_jobs_on_active_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_active_job_id ON public.solid_queue_jobs USING btree (active_job_id);


--
-- Name: index_solid_queue_jobs_on_class_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_class_name ON public.solid_queue_jobs USING btree (class_name);


--
-- Name: index_solid_queue_jobs_on_finished_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_finished_at ON public.solid_queue_jobs USING btree (finished_at);


--
-- Name: index_solid_queue_pauses_on_queue_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_pauses_on_queue_name ON public.solid_queue_pauses USING btree (queue_name);


--
-- Name: index_solid_queue_poll_all; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_poll_all ON public.solid_queue_ready_executions USING btree (priority, job_id);


--
-- Name: index_solid_queue_poll_by_queue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_poll_by_queue ON public.solid_queue_ready_executions USING btree (queue_name, priority, job_id);


--
-- Name: index_solid_queue_processes_on_last_heartbeat_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_processes_on_last_heartbeat_at ON public.solid_queue_processes USING btree (last_heartbeat_at);


--
-- Name: index_solid_queue_processes_on_name_and_supervisor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_processes_on_name_and_supervisor_id ON public.solid_queue_processes USING btree (name, supervisor_id);


--
-- Name: index_solid_queue_processes_on_supervisor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_processes_on_supervisor_id ON public.solid_queue_processes USING btree (supervisor_id);


--
-- Name: index_solid_queue_ready_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_ready_executions_on_job_id ON public.solid_queue_ready_executions USING btree (job_id);


--
-- Name: index_solid_queue_recurring_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_executions_on_job_id ON public.solid_queue_recurring_executions USING btree (job_id);


--
-- Name: index_solid_queue_recurring_executions_on_task_key_and_run_at; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_executions_on_task_key_and_run_at ON public.solid_queue_recurring_executions USING btree (task_key, run_at);


--
-- Name: index_solid_queue_recurring_tasks_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_tasks_on_key ON public.solid_queue_recurring_tasks USING btree (key);


--
-- Name: index_solid_queue_recurring_tasks_on_static; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_recurring_tasks_on_static ON public.solid_queue_recurring_tasks USING btree (static);


--
-- Name: index_solid_queue_scheduled_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_scheduled_executions_on_job_id ON public.solid_queue_scheduled_executions USING btree (job_id);


--
-- Name: index_solid_queue_semaphores_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_semaphores_on_expires_at ON public.solid_queue_semaphores USING btree (expires_at);


--
-- Name: index_solid_queue_semaphores_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_semaphores_on_key ON public.solid_queue_semaphores USING btree (key);


--
-- Name: index_solid_queue_semaphores_on_key_and_value; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_semaphores_on_key_and_value ON public.solid_queue_semaphores USING btree (key, value);


--
-- Name: index_store_shifts_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_store_shifts_on_admin_user_id ON public.store_shifts USING btree (admin_user_id);


--
-- Name: index_store_shifts_on_store_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_store_shifts_on_store_id ON public.store_shifts USING btree (store_id);


--
-- Name: index_store_shifts_on_store_id_and_day_of_week; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_store_shifts_on_store_id_and_day_of_week ON public.store_shifts USING btree (store_id, day_of_week);


--
-- Name: index_store_shifts_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_store_shifts_on_tenant_id ON public.store_shifts USING btree (tenant_id);


--
-- Name: index_stores_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stores_on_active ON public.stores USING btree (active);


--
-- Name: index_stores_on_director_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stores_on_director_admin_user_id ON public.stores USING btree (director_admin_user_id);


--
-- Name: index_stores_on_footer_store_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stores_on_footer_store_id ON public.stores USING btree (footer_store_id);


--
-- Name: index_stores_on_location; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stores_on_location ON public.stores USING gist (location);


--
-- Name: index_stores_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_stores_on_slug ON public.stores USING btree (slug);


--
-- Name: index_stores_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stores_on_tenant_id ON public.stores USING btree (tenant_id);


--
-- Name: index_stores_on_tenant_id_and_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stores_on_tenant_id_and_active ON public.stores USING btree (tenant_id, active);


--
-- Name: index_stores_on_turnos_config; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stores_on_turnos_config ON public.stores USING gin (turnos_config);


--
-- Name: index_tasks_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_admin_user_id ON public.tasks USING btree (admin_user_id);


--
-- Name: index_tasks_on_admin_user_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_admin_user_id_and_status ON public.tasks USING btree (admin_user_id, status);


--
-- Name: index_tasks_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_created_by_id ON public.tasks USING btree (created_by_id);


--
-- Name: index_tasks_on_due_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_due_at ON public.tasks USING btree (due_at);


--
-- Name: index_tasks_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_lead_id ON public.tasks USING btree (lead_id);


--
-- Name: index_tasks_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_tenant_id ON public.tasks USING btree (tenant_id);


--
-- Name: index_tasks_on_tenant_id_and_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_tenant_id_and_admin_user_id ON public.tasks USING btree (tenant_id, admin_user_id);


--
-- Name: index_tenants_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tenants_on_slug ON public.tenants USING btree (slug);


--
-- Name: index_trusted_devices_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trusted_devices_on_admin_user_id ON public.trusted_devices USING btree (admin_user_id);


--
-- Name: index_trusted_devices_on_admin_user_id_and_fingerprint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_trusted_devices_on_admin_user_id_and_fingerprint ON public.trusted_devices USING btree (admin_user_id, fingerprint);


--
-- Name: index_trusted_devices_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trusted_devices_on_created_by_id ON public.trusted_devices USING btree (created_by_id);


--
-- Name: index_trusted_devices_on_last_ip; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trusted_devices_on_last_ip ON public.trusted_devices USING btree (last_ip);


--
-- Name: index_trusted_devices_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trusted_devices_on_status ON public.trusted_devices USING btree (status);


--
-- Name: index_trusted_devices_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_trusted_devices_on_tenant_id ON public.trusted_devices USING btree (tenant_id);


--
-- Name: index_trusted_devices_on_tenant_user_fingerprint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_trusted_devices_on_tenant_user_fingerprint ON public.trusted_devices USING btree (tenant_id, admin_user_id, fingerprint);


--
-- Name: index_user_meta_integrations_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_meta_integrations_on_admin_user_id ON public.user_meta_integrations USING btree (admin_user_id);


--
-- Name: index_user_meta_integrations_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_meta_integrations_on_tenant_id ON public.user_meta_integrations USING btree (tenant_id);


--
-- Name: index_vista_file_assets_on_active_storage_attachment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vista_file_assets_on_active_storage_attachment_id ON public.vista_file_assets USING btree (active_storage_attachment_id);


--
-- Name: index_vista_file_assets_on_active_storage_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vista_file_assets_on_active_storage_key ON public.vista_file_assets USING btree (active_storage_key);


--
-- Name: index_vista_file_assets_on_codigo_imovel_and_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vista_file_assets_on_codigo_imovel_and_kind ON public.vista_file_assets USING btree (codigo_imovel, kind);


--
-- Name: index_vista_file_assets_on_habitation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vista_file_assets_on_habitation_id ON public.vista_file_assets USING btree (habitation_id);


--
-- Name: index_vista_file_assets_on_status_and_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vista_file_assets_on_status_and_kind ON public.vista_file_assets USING btree (status, kind);


--
-- Name: index_vista_file_assets_on_vista_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vista_file_assets_on_vista_import_batch_id ON public.vista_file_assets USING btree (vista_import_batch_id);


--
-- Name: index_vista_file_assets_on_vista_raw_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vista_file_assets_on_vista_raw_record_id ON public.vista_file_assets USING btree (vista_raw_record_id);


--
-- Name: index_vista_import_batches_on_dump_dir; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vista_import_batches_on_dump_dir ON public.vista_import_batches USING btree (dump_dir);


--
-- Name: index_vista_import_batches_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vista_import_batches_on_status ON public.vista_import_batches USING btree (status);


--
-- Name: index_vista_raw_records_on_payload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vista_raw_records_on_payload ON public.vista_raw_records USING gin (payload);


--
-- Name: index_vista_raw_records_on_table_name_and_codigo_cliente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vista_raw_records_on_table_name_and_codigo_cliente ON public.vista_raw_records USING btree (table_name, codigo_cliente);


--
-- Name: index_vista_raw_records_on_table_name_and_codigo_corretor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vista_raw_records_on_table_name_and_codigo_corretor ON public.vista_raw_records USING btree (table_name, codigo_corretor);


--
-- Name: index_vista_raw_records_on_table_name_and_codigo_imovel; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vista_raw_records_on_table_name_and_codigo_imovel ON public.vista_raw_records USING btree (table_name, codigo_imovel);


--
-- Name: index_vista_raw_records_on_table_name_and_source_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vista_raw_records_on_table_name_and_source_key ON public.vista_raw_records USING btree (table_name, source_key);


--
-- Name: index_vista_raw_records_on_vista_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vista_raw_records_on_vista_import_batch_id ON public.vista_raw_records USING btree (vista_import_batch_id);


--
-- Name: index_wa_campaign_messages_on_tenant_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_wa_campaign_messages_on_tenant_and_external_id ON public.whatsapp_campaign_messages USING btree (tenant_id, external_message_id) WHERE (external_message_id IS NOT NULL);


--
-- Name: index_wa_conversations_on_tenant_and_bsuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_wa_conversations_on_tenant_and_bsuid ON public.whatsapp_conversations USING btree (tenant_id, business_scoped_user_id) WHERE (business_scoped_user_id IS NOT NULL);


--
-- Name: index_wa_conversations_on_tenant_and_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_wa_conversations_on_tenant_and_phone ON public.whatsapp_conversations USING btree (tenant_id, contact_phone) WHERE (contact_phone IS NOT NULL);


--
-- Name: index_whatsapp_business_integrations_on_phone_number_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_business_integrations_on_phone_number_id ON public.whatsapp_business_integrations USING btree (phone_number_id);


--
-- Name: index_whatsapp_business_integrations_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_business_integrations_on_status ON public.whatsapp_business_integrations USING btree (status);


--
-- Name: index_whatsapp_business_integrations_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_business_integrations_on_tenant_id ON public.whatsapp_business_integrations USING btree (tenant_id);


--
-- Name: index_whatsapp_business_integrations_on_tenant_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_business_integrations_on_tenant_id_and_status ON public.whatsapp_business_integrations USING btree (tenant_id, status);


--
-- Name: index_whatsapp_business_integrations_on_waba_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_business_integrations_on_waba_id ON public.whatsapp_business_integrations USING btree (waba_id);


--
-- Name: index_whatsapp_campaign_messages_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaign_messages_on_lead_id ON public.whatsapp_campaign_messages USING btree (lead_id);


--
-- Name: index_whatsapp_campaign_messages_on_next_retry_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaign_messages_on_next_retry_at ON public.whatsapp_campaign_messages USING btree (next_retry_at);


--
-- Name: index_whatsapp_campaign_messages_on_reply_button_text; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaign_messages_on_reply_button_text ON public.whatsapp_campaign_messages USING btree (reply_button_text);


--
-- Name: index_whatsapp_campaign_messages_on_reply_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaign_messages_on_reply_type ON public.whatsapp_campaign_messages USING btree (reply_type);


--
-- Name: index_whatsapp_campaign_messages_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaign_messages_on_status ON public.whatsapp_campaign_messages USING btree (status);


--
-- Name: index_whatsapp_campaign_messages_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaign_messages_on_tenant_id ON public.whatsapp_campaign_messages USING btree (tenant_id);


--
-- Name: index_whatsapp_campaign_messages_on_whatsapp_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaign_messages_on_whatsapp_campaign_id ON public.whatsapp_campaign_messages USING btree (whatsapp_campaign_id);


--
-- Name: index_whatsapp_campaign_messages_on_whatsapp_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaign_messages_on_whatsapp_message_id ON public.whatsapp_campaign_messages USING btree (whatsapp_message_id);


--
-- Name: index_whatsapp_campaign_recipients_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaign_recipients_on_admin_user_id ON public.whatsapp_campaign_recipients USING btree (admin_user_id);


--
-- Name: index_whatsapp_campaign_recipients_on_conversion_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaign_recipients_on_conversion_status ON public.whatsapp_campaign_recipients USING btree (conversion_status);


--
-- Name: index_whatsapp_campaign_recipients_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaign_recipients_on_lead_id ON public.whatsapp_campaign_recipients USING btree (lead_id);


--
-- Name: index_whatsapp_campaign_recipients_on_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaign_recipients_on_source ON public.whatsapp_campaign_recipients USING btree (source);


--
-- Name: index_whatsapp_campaign_recipients_on_tags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaign_recipients_on_tags ON public.whatsapp_campaign_recipients USING gin (tags);


--
-- Name: index_whatsapp_campaign_recipients_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaign_recipients_on_tenant_id ON public.whatsapp_campaign_recipients USING btree (tenant_id);


--
-- Name: index_whatsapp_campaign_recipients_on_whatsapp_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaign_recipients_on_whatsapp_campaign_id ON public.whatsapp_campaign_recipients USING btree (whatsapp_campaign_id);


--
-- Name: index_whatsapp_campaign_unsubscribes_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaign_unsubscribes_on_tenant_id ON public.whatsapp_campaign_unsubscribes USING btree (tenant_id);


--
-- Name: index_whatsapp_campaigns_on_audience_definition; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaigns_on_audience_definition ON public.whatsapp_campaigns USING gin (audience_definition);


--
-- Name: index_whatsapp_campaigns_on_audience_mode; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaigns_on_audience_mode ON public.whatsapp_campaigns USING btree (audience_mode);


--
-- Name: index_whatsapp_campaigns_on_automation_workflow_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaigns_on_automation_workflow_id ON public.whatsapp_campaigns USING btree (automation_workflow_id);


--
-- Name: index_whatsapp_campaigns_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaigns_on_created_at ON public.whatsapp_campaigns USING btree (created_at);


--
-- Name: index_whatsapp_campaigns_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaigns_on_created_by_id ON public.whatsapp_campaigns USING btree (created_by_id);


--
-- Name: index_whatsapp_campaigns_on_group_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaigns_on_group_name ON public.whatsapp_campaigns USING btree (group_name);


--
-- Name: index_whatsapp_campaigns_on_scheduled_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaigns_on_scheduled_at ON public.whatsapp_campaigns USING btree (scheduled_at);


--
-- Name: index_whatsapp_campaigns_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaigns_on_status ON public.whatsapp_campaigns USING btree (status);


--
-- Name: index_whatsapp_campaigns_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaigns_on_tenant_id ON public.whatsapp_campaigns USING btree (tenant_id);


--
-- Name: index_whatsapp_campaigns_on_tenant_id_and_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaigns_on_tenant_id_and_created_by_id ON public.whatsapp_campaigns USING btree (tenant_id, created_by_id);


--
-- Name: index_whatsapp_campaigns_on_whatsapp_sender_number_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaigns_on_whatsapp_sender_number_id ON public.whatsapp_campaigns USING btree (whatsapp_sender_number_id);


--
-- Name: index_whatsapp_campaigns_on_whatsapp_template_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_campaigns_on_whatsapp_template_id ON public.whatsapp_campaigns USING btree (whatsapp_template_id);


--
-- Name: index_whatsapp_conversations_on_assigned_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_conversations_on_assigned_admin_user_id ON public.whatsapp_conversations USING btree (assigned_admin_user_id);


--
-- Name: index_whatsapp_conversations_on_last_message_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_conversations_on_last_message_at ON public.whatsapp_conversations USING btree (last_message_at);


--
-- Name: index_whatsapp_conversations_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_conversations_on_lead_id ON public.whatsapp_conversations USING btree (lead_id);


--
-- Name: index_whatsapp_conversations_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_conversations_on_tenant_id ON public.whatsapp_conversations USING btree (tenant_id);


--
-- Name: index_whatsapp_conversations_on_tenant_id_and_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_conversations_on_tenant_id_and_lead_id ON public.whatsapp_conversations USING btree (tenant_id, lead_id);


--
-- Name: index_whatsapp_messages_on_admin_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_messages_on_admin_user_id ON public.whatsapp_messages USING btree (admin_user_id);


--
-- Name: index_whatsapp_messages_on_context_wa_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_messages_on_context_wa_message_id ON public.whatsapp_messages USING btree (context_wa_message_id);


--
-- Name: index_whatsapp_messages_on_conversation_pinned; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_messages_on_conversation_pinned ON public.whatsapp_messages USING btree (whatsapp_conversation_id, pinned_at);


--
-- Name: index_whatsapp_messages_on_presentation_card_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_messages_on_presentation_card_id ON public.whatsapp_messages USING btree (presentation_card_id);


--
-- Name: index_whatsapp_messages_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_messages_on_tenant_id ON public.whatsapp_messages USING btree (tenant_id);


--
-- Name: index_whatsapp_messages_on_tenant_id_and_wa_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_whatsapp_messages_on_tenant_id_and_wa_message_id ON public.whatsapp_messages USING btree (tenant_id, wa_message_id) WHERE (wa_message_id IS NOT NULL);


--
-- Name: index_whatsapp_messages_on_wa_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_messages_on_wa_message_id ON public.whatsapp_messages USING btree (wa_message_id);


--
-- Name: index_whatsapp_messages_on_whatsapp_conversation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_messages_on_whatsapp_conversation_id ON public.whatsapp_messages USING btree (whatsapp_conversation_id);


--
-- Name: index_whatsapp_sender_numbers_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_sender_numbers_on_active ON public.whatsapp_sender_numbers USING btree (active);


--
-- Name: index_whatsapp_sender_numbers_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_sender_numbers_on_status ON public.whatsapp_sender_numbers USING btree (status);


--
-- Name: index_whatsapp_sender_numbers_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_sender_numbers_on_tenant_id ON public.whatsapp_sender_numbers USING btree (tenant_id);


--
-- Name: index_whatsapp_sender_numbers_on_tenant_id_and_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_sender_numbers_on_tenant_id_and_active ON public.whatsapp_sender_numbers USING btree (tenant_id, active);


--
-- Name: index_whatsapp_sender_numbers_on_tenant_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_sender_numbers_on_tenant_id_and_status ON public.whatsapp_sender_numbers USING btree (tenant_id, status);


--
-- Name: index_whatsapp_templates_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_templates_on_status ON public.whatsapp_templates USING btree (status);


--
-- Name: index_whatsapp_templates_on_template_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_templates_on_template_type ON public.whatsapp_templates USING btree (template_type);


--
-- Name: index_whatsapp_templates_on_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_templates_on_tenant_id ON public.whatsapp_templates USING btree (tenant_id);


--
-- Name: index_whatsapp_templates_on_tenant_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_whatsapp_templates_on_tenant_id_and_status ON public.whatsapp_templates USING btree (tenant_id, status);


--
-- Name: access_audit_logs access_audit_logs_no_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER access_audit_logs_no_update BEFORE DELETE OR UPDATE ON public.access_audit_logs FOR EACH ROW EXECUTE FUNCTION public.raise_access_audit_immutable();


--
-- Name: checkin_audit_logs checkin_audit_logs_no_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER checkin_audit_logs_no_update BEFORE DELETE OR UPDATE ON public.checkin_audit_logs FOR EACH ROW EXECUTE FUNCTION public.raise_checkin_audit_immutable();


--
-- Name: data_export_audit_logs data_export_audit_logs_no_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER data_export_audit_logs_no_update BEFORE DELETE OR UPDATE ON public.data_export_audit_logs FOR EACH ROW EXECUTE FUNCTION public.raise_data_export_audit_immutable();


--
-- Name: habitation_audit_logs habitation_audit_logs_no_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER habitation_audit_logs_no_update BEFORE DELETE OR UPDATE ON public.habitation_audit_logs FOR EACH ROW EXECUTE FUNCTION public.raise_habitation_audit_immutable();


--
-- Name: lead_audit_logs lead_audit_logs_no_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER lead_audit_logs_no_update BEFORE DELETE OR UPDATE ON public.lead_audit_logs FOR EACH ROW EXECUTE FUNCTION public.raise_lead_audit_immutable();


--
-- Name: access_audit_logs trigger_enforce_access_audit_log_tenant_governance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_enforce_access_audit_log_tenant_governance BEFORE INSERT OR UPDATE OF tenant_id, admin_user_id ON public.access_audit_logs FOR EACH ROW EXECUTE FUNCTION public.enforce_access_audit_log_tenant_governance();


--
-- Name: admin_users trigger_enforce_admin_user_profile_governance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_enforce_admin_user_profile_governance BEFORE INSERT OR UPDATE OF tenant_id, profile_id, horizontal_profile_id, manager_id ON public.admin_users FOR EACH ROW EXECUTE FUNCTION public.enforce_admin_user_profile_governance();


--
-- Name: profiles trigger_enforce_profile_axis_governance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_enforce_profile_axis_governance BEFORE INSERT OR UPDATE OF tenant_id, axis, vertical_profile_id ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.enforce_profile_axis_governance();


--
-- Name: trusted_devices trigger_enforce_trusted_device_tenant_governance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_enforce_trusted_device_tenant_governance BEFORE INSERT OR UPDATE OF tenant_id, admin_user_id ON public.trusted_devices FOR EACH ROW EXECUTE FUNCTION public.enforce_trusted_device_tenant_governance();


--
-- Name: admin_users fk_admin_users_horizontal_profile_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT fk_admin_users_horizontal_profile_same_tenant FOREIGN KEY (horizontal_profile_id, tenant_id) REFERENCES public.profiles(id, tenant_id) NOT VALID;


--
-- Name: admin_users fk_admin_users_manager_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT fk_admin_users_manager_same_tenant FOREIGN KEY (manager_id, tenant_id) REFERENCES public.admin_users(id, tenant_id) NOT VALID;


--
-- Name: admin_users fk_admin_users_profile_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT fk_admin_users_profile_same_tenant FOREIGN KEY (profile_id, tenant_id) REFERENCES public.profiles(id, tenant_id) NOT VALID;


--
-- Name: profiles fk_profiles_vertical_profile_same_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT fk_profiles_vertical_profile_same_tenant FOREIGN KEY (vertical_profile_id, tenant_id) REFERENCES public.profiles(id, tenant_id) NOT VALID;


--
-- Name: lead_labels fk_rails_0318289c3b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_labels
    ADD CONSTRAINT fk_rails_0318289c3b FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: store_shifts fk_rails_0416b68456; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_shifts
    ADD CONSTRAINT fk_rails_0416b68456 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: lead_audit_logs fk_rails_0468a96dcf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_audit_logs
    ADD CONSTRAINT fk_rails_0468a96dcf FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: whatsapp_campaign_unsubscribes fk_rails_05ee37a843; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_unsubscribes
    ADD CONSTRAINT fk_rails_05ee37a843 FOREIGN KEY (whatsapp_campaign_recipient_id) REFERENCES public.whatsapp_campaign_recipients(id);


--
-- Name: email_settings fk_rails_09c40e8cf2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_settings
    ADD CONSTRAINT fk_rails_09c40e8cf2 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: whatsapp_sender_numbers fk_rails_0b40b13075; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_sender_numbers
    ADD CONSTRAINT fk_rails_0b40b13075 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: whatsapp_campaign_recipients fk_rails_0bf1e1cab0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_recipients
    ADD CONSTRAINT fk_rails_0bf1e1cab0 FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: automation_executions fk_rails_0e273bfb0b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_executions
    ADD CONSTRAINT fk_rails_0e273bfb0b FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: habitation_share_links fk_rails_0e80d0e62c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_share_links
    ADD CONSTRAINT fk_rails_0e80d0e62c FOREIGN KEY (habitation_id) REFERENCES public.habitations(id);


--
-- Name: leads fk_rails_0ed786c31e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT fk_rails_0ed786c31e FOREIGN KEY (shared_by_admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: presentation_cards fk_rails_1053763516; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presentation_cards
    ADD CONSTRAINT fk_rails_1053763516 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: captacoes fk_rails_121e1dda03; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.captacoes
    ADD CONSTRAINT fk_rails_121e1dda03 FOREIGN KEY (corretor_id) REFERENCES public.admin_users(id);


--
-- Name: whatsapp_campaign_unsubscribes fk_rails_13334d8900; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_unsubscribes
    ADD CONSTRAINT fk_rails_13334d8900 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: habitation_exports fk_rails_144190f564; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_exports
    ADD CONSTRAINT fk_rails_144190f564 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: footer_links fk_rails_14fda2a7a0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.footer_links
    ADD CONSTRAINT fk_rails_14fda2a7a0 FOREIGN KEY (footer_setting_id) REFERENCES public.footer_settings(id);


--
-- Name: public_navigation_events fk_rails_1681cf0713; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.public_navigation_events
    ADD CONSTRAINT fk_rails_1681cf0713 FOREIGN KEY (public_navigation_session_id) REFERENCES public.public_navigation_sessions(id);


--
-- Name: ai_property_suggestions fk_rails_16f184cd4c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_property_suggestions
    ADD CONSTRAINT fk_rails_16f184cd4c FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: admin_users fk_rails_18edaf9350; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT fk_rails_18edaf9350 FOREIGN KEY (rentals_manager_id) REFERENCES public.admin_users(id);


--
-- Name: stores fk_rails_19c4970b14; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT fk_rails_19c4970b14 FOREIGN KEY (director_admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: inbound_webhook_tokens fk_rails_1c174f9f08; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_webhook_tokens
    ADD CONSTRAINT fk_rails_1c174f9f08 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: automation_workflow_versions fk_rails_1cd4d6081b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_workflow_versions
    ADD CONSTRAINT fk_rails_1cd4d6081b FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: leads fk_rails_20d5a6bd75; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT fk_rails_20d5a6bd75 FOREIGN KEY (distribution_rule_id) REFERENCES public.distribution_rules(id);


--
-- Name: client_interactions fk_rails_217d5c3605; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_interactions
    ADD CONSTRAINT fk_rails_217d5c3605 FOREIGN KEY (crm_contact_id) REFERENCES public.crm_contacts(id);


--
-- Name: whatsapp_messages fk_rails_2263286ba5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_messages
    ADD CONSTRAINT fk_rails_2263286ba5 FOREIGN KEY (presentation_card_id) REFERENCES public.presentation_cards(id);


--
-- Name: seo_focus_keywords fk_rails_23d9a9ce43; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_focus_keywords
    ADD CONSTRAINT fk_rails_23d9a9ce43 FOREIGN KEY (seo_setting_id) REFERENCES public.seo_settings(id);


--
-- Name: portal_integration_events fk_rails_23eb6add0b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_integration_events
    ADD CONSTRAINT fk_rails_23eb6add0b FOREIGN KEY (habitation_id) REFERENCES public.habitations(id);


--
-- Name: client_property_interests fk_rails_25d4f01b1f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_property_interests
    ADD CONSTRAINT fk_rails_25d4f01b1f FOREIGN KEY (habitation_id) REFERENCES public.habitations(id);


--
-- Name: whatsapp_campaign_messages fk_rails_26131b72dd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_messages
    ADD CONSTRAINT fk_rails_26131b72dd FOREIGN KEY (whatsapp_message_id) REFERENCES public.whatsapp_messages(id);


--
-- Name: whatsapp_campaigns fk_rails_26c34a4ecc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaigns
    ADD CONSTRAINT fk_rails_26c34a4ecc FOREIGN KEY (created_by_id) REFERENCES public.admin_users(id);


--
-- Name: habitation_share_links fk_rails_2772a86517; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_share_links
    ADD CONSTRAINT fk_rails_2772a86517 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: crm_appointments fk_rails_277c650c4d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_appointments
    ADD CONSTRAINT fk_rails_277c650c4d FOREIGN KEY (crm_contact_id) REFERENCES public.crm_contacts(id);


--
-- Name: seo_change_logs fk_rails_27eda6d4a6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_change_logs
    ADD CONSTRAINT fk_rails_27eda6d4a6 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: checkin_audit_logs fk_rails_281c7e6935; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checkin_audit_logs
    ADD CONSTRAINT fk_rails_281c7e6935 FOREIGN KEY (check_in_id) REFERENCES public.check_ins(id);


--
-- Name: automation_runs fk_rails_2a2959b596; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_runs
    ADD CONSTRAINT fk_rails_2a2959b596 FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: whatsapp_messages fk_rails_2c031c7799; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_messages
    ADD CONSTRAINT fk_rails_2c031c7799 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: automation_executions fk_rails_2caf5b71f7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_executions
    ADD CONSTRAINT fk_rails_2caf5b71f7 FOREIGN KEY (automation_workflow_version_id) REFERENCES public.automation_workflow_versions(id);


--
-- Name: distribution_rule_agents fk_rails_2ff40d37bc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.distribution_rule_agents
    ADD CONSTRAINT fk_rails_2ff40d37bc FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: automation_workflows fk_rails_303e030651; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_workflows
    ADD CONSTRAINT fk_rails_303e030651 FOREIGN KEY (active_version_id) REFERENCES public.automation_workflow_versions(id);


--
-- Name: client_interactions fk_rails_3070096ac7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_interactions
    ADD CONSTRAINT fk_rails_3070096ac7 FOREIGN KEY (proprietor_id) REFERENCES public.proprietors(id);


--
-- Name: solid_queue_recurring_executions fk_rails_318a5533ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions
    ADD CONSTRAINT fk_rails_318a5533ed FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: marketing_campaigns fk_rails_32263aaa14; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketing_campaigns
    ADD CONSTRAINT fk_rails_32263aaa14 FOREIGN KEY (seo_setting_id) REFERENCES public.seo_settings(id);


--
-- Name: data_export_audit_logs fk_rails_330294625a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_export_audit_logs
    ADD CONSTRAINT fk_rails_330294625a FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: profiles fk_rails_350dbd643d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT fk_rails_350dbd643d FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: seo_conversion_events fk_rails_354f47c6c3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_conversion_events
    ADD CONSTRAINT fk_rails_354f47c6c3 FOREIGN KEY (seo_setting_id) REFERENCES public.seo_settings(id);


--
-- Name: check_ins fk_rails_381f0953e0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_ins
    ADD CONSTRAINT fk_rails_381f0953e0 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: account_memberships fk_rails_3925c6af0c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_memberships
    ADD CONSTRAINT fk_rails_3925c6af0c FOREIGN KEY (primary_admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: solid_queue_failed_executions fk_rails_39bbc7a631; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions
    ADD CONSTRAINT fk_rails_39bbc7a631 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: public_navigation_events fk_rails_39c3972f50; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.public_navigation_events
    ADD CONSTRAINT fk_rails_39c3972f50 FOREIGN KEY (habitation_id) REFERENCES public.habitations(id);


--
-- Name: settings fk_rails_3a7e6495d2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT fk_rails_3a7e6495d2 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: access_control_rules fk_rails_3a9287ea7a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_control_rules
    ADD CONSTRAINT fk_rails_3a9287ea7a FOREIGN KEY (created_by_id) REFERENCES public.admin_users(id);


--
-- Name: leads fk_rails_3b8845bac5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT fk_rails_3b8845bac5 FOREIGN KEY (vista_import_batch_id) REFERENCES public.vista_import_batches(id);


--
-- Name: automation_webhook_deliveries fk_rails_3e8969d1cd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_webhook_deliveries
    ADD CONSTRAINT fk_rails_3e8969d1cd FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: account_memberships fk_rails_3fbff27fad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_memberships
    ADD CONSTRAINT fk_rails_3fbff27fad FOREIGN KEY (member_admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: whatsapp_messages fk_rails_406746be40; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_messages
    ADD CONSTRAINT fk_rails_406746be40 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: appointments fk_rails_42e3b238ee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_rails_42e3b238ee FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: distribution_rule_agents fk_rails_43433f55b6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.distribution_rule_agents
    ADD CONSTRAINT fk_rails_43433f55b6 FOREIGN KEY (distribution_rule_id) REFERENCES public.distribution_rules(id);


--
-- Name: vista_file_assets fk_rails_434988960e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vista_file_assets
    ADD CONSTRAINT fk_rails_434988960e FOREIGN KEY (vista_import_batch_id) REFERENCES public.vista_import_batches(id);


--
-- Name: public_navigation_sessions fk_rails_43befe6943; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.public_navigation_sessions
    ADD CONSTRAINT fk_rails_43befe6943 FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: habitations fk_rails_469bb01085; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitations
    ADD CONSTRAINT fk_rails_469bb01085 FOREIGN KEY (constructor_id) REFERENCES public.constructors(id);


--
-- Name: trusted_devices fk_rails_4780fd9ba4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trusted_devices
    ADD CONSTRAINT fk_rails_4780fd9ba4 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: habitations fk_rails_49efca6fdb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitations
    ADD CONSTRAINT fk_rails_49efca6fdb FOREIGN KEY (proprietor_id) REFERENCES public.proprietors(id);


--
-- Name: whatsapp_conversations fk_rails_4c2819349d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_conversations
    ADD CONSTRAINT fk_rails_4c2819349d FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: solid_queue_blocked_executions fk_rails_4cd34e2228; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions
    ADD CONSTRAINT fk_rails_4cd34e2228 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: automation_workflows fk_rails_4cf5f305c9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_workflows
    ADD CONSTRAINT fk_rails_4cf5f305c9 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: push_delivery_events fk_rails_4e2921ec0c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_delivery_events
    ADD CONSTRAINT fk_rails_4e2921ec0c FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: vista_file_assets fk_rails_4efde7904b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vista_file_assets
    ADD CONSTRAINT fk_rails_4efde7904b FOREIGN KEY (habitation_id) REFERENCES public.habitations(id);


--
-- Name: check_ins fk_rails_4ffa2041a7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_ins
    ADD CONSTRAINT fk_rails_4ffa2041a7 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: seo_conversion_events fk_rails_52d0966b31; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_conversion_events
    ADD CONSTRAINT fk_rails_52d0966b31 FOREIGN KEY (habitation_id) REFERENCES public.habitations(id);


--
-- Name: meta_facebook_pages fk_rails_5348759d86; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meta_facebook_pages
    ADD CONSTRAINT fk_rails_5348759d86 FOREIGN KEY (user_meta_integration_id) REFERENCES public.user_meta_integrations(id);


--
-- Name: ai_property_suggestions fk_rails_5396749713; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_property_suggestions
    ADD CONSTRAINT fk_rails_5396749713 FOREIGN KEY (habitation_id) REFERENCES public.habitations(id);


--
-- Name: crm_appointments fk_rails_53de7c076e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_appointments
    ADD CONSTRAINT fk_rails_53de7c076e FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: automation_webhook_deliveries fk_rails_54434d3d00; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_webhook_deliveries
    ADD CONSTRAINT fk_rails_54434d3d00 FOREIGN KEY (automation_run_id) REFERENCES public.automation_runs(id);


--
-- Name: location_pings fk_rails_550bb129fb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location_pings
    ADD CONSTRAINT fk_rails_550bb129fb FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: push_delivery_events fk_rails_554cf67930; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_delivery_events
    ADD CONSTRAINT fk_rails_554cf67930 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: client_property_interests fk_rails_5562a97d6c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_property_interests
    ADD CONSTRAINT fk_rails_5562a97d6c FOREIGN KEY (crm_contact_id) REFERENCES public.crm_contacts(id);


--
-- Name: google_maps_integration_settings fk_rails_55dd38d915; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.google_maps_integration_settings
    ADD CONSTRAINT fk_rails_55dd38d915 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: lead_labelings fk_rails_570d08d6e8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_labelings
    ADD CONSTRAINT fk_rails_570d08d6e8 FOREIGN KEY (lead_label_id) REFERENCES public.lead_labels(id);


--
-- Name: whatsapp_campaigns fk_rails_570e00c34f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaigns
    ADD CONSTRAINT fk_rails_570e00c34f FOREIGN KEY (whatsapp_template_id) REFERENCES public.whatsapp_templates(id);


--
-- Name: check_ins fk_rails_58d2ce0005; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_ins
    ADD CONSTRAINT fk_rails_58d2ce0005 FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- Name: appointments fk_rails_58fcae7c3d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_rails_58fcae7c3d FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: account_memberships fk_rails_5911c0386d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_memberships
    ADD CONSTRAINT fk_rails_5911c0386d FOREIGN KEY (horizontal_profile_id) REFERENCES public.profiles(id);


--
-- Name: admin_users fk_rails_591ae579ef; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT fk_rails_591ae579ef FOREIGN KEY (profile_id) REFERENCES public.profiles(id);


--
-- Name: notification_template_settings fk_rails_5a780d873b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_template_settings
    ADD CONSTRAINT fk_rails_5a780d873b FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: account_memberships fk_rails_5bb672184e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_memberships
    ADD CONSTRAINT fk_rails_5bb672184e FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: home_section_items fk_rails_5d2e2b9dc2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.home_section_items
    ADD CONSTRAINT fk_rails_5d2e2b9dc2 FOREIGN KEY (home_section_id) REFERENCES public.home_sections(id);


--
-- Name: client_interactions fk_rails_5d58b5c954; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_interactions
    ADD CONSTRAINT fk_rails_5d58b5c954 FOREIGN KEY (vista_import_batch_id) REFERENCES public.vista_import_batches(id);


--
-- Name: whatsapp_campaign_unsubscribes fk_rails_5fa226f99c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_unsubscribes
    ADD CONSTRAINT fk_rails_5fa226f99c FOREIGN KEY (whatsapp_campaign_id) REFERENCES public.whatsapp_campaigns(id);


--
-- Name: home_hero_slides fk_rails_612e24602a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.home_hero_slides
    ADD CONSTRAINT fk_rails_612e24602a FOREIGN KEY (home_setting_id) REFERENCES public.home_settings(id);


--
-- Name: property_settings fk_rails_6235033dd9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_settings
    ADD CONSTRAINT fk_rails_6235033dd9 FOREIGN KEY (broker_capture_fallback_admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: automation_runs fk_rails_62830c56f1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_runs
    ADD CONSTRAINT fk_rails_62830c56f1 FOREIGN KEY (automation_event_id) REFERENCES public.automation_events(id);


--
-- Name: proposals fk_rails_630ac967de; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proposals
    ADD CONSTRAINT fk_rails_630ac967de FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: proprietors fk_rails_63e65bb6ac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proprietors
    ADD CONSTRAINT fk_rails_63e65bb6ac FOREIGN KEY (vista_import_batch_id) REFERENCES public.vista_import_batches(id);


--
-- Name: whatsapp_campaign_unsubscribes fk_rails_658c0aa041; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_unsubscribes
    ADD CONSTRAINT fk_rails_658c0aa041 FOREIGN KEY (reenabled_by_id) REFERENCES public.admin_users(id);


--
-- Name: whatsapp_sender_numbers fk_rails_6af8b1646a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_sender_numbers
    ADD CONSTRAINT fk_rails_6af8b1646a FOREIGN KEY (whatsapp_business_integration_id) REFERENCES public.whatsapp_business_integrations(id);


--
-- Name: seo_page_visits fk_rails_6b14e26baa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_page_visits
    ADD CONSTRAINT fk_rails_6b14e26baa FOREIGN KEY (seo_setting_id) REFERENCES public.seo_settings(id);


--
-- Name: lead_property_interests fk_rails_6d086c5d31; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_property_interests
    ADD CONSTRAINT fk_rails_6d086c5d31 FOREIGN KEY (habitation_id) REFERENCES public.habitations(id);


--
-- Name: habitation_photo_shares fk_rails_6dc09f5171; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_photo_shares
    ADD CONSTRAINT fk_rails_6dc09f5171 FOREIGN KEY (habitation_id) REFERENCES public.habitations(id);


--
-- Name: habitation_interactions fk_rails_6e8270cc0c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_interactions
    ADD CONSTRAINT fk_rails_6e8270cc0c FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: whatsapp_campaign_messages fk_rails_6efdbc3737; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_messages
    ADD CONSTRAINT fk_rails_6efdbc3737 FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: portal_integrations fk_rails_70282156d0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_integrations
    ADD CONSTRAINT fk_rails_70282156d0 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: whatsapp_templates fk_rails_737f4f7e1b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_templates
    ADD CONSTRAINT fk_rails_737f4f7e1b FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: lead_labelings fk_rails_738b0d3086; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_labelings
    ADD CONSTRAINT fk_rails_738b0d3086 FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: account_memberships fk_rails_7548887bd0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_memberships
    ADD CONSTRAINT fk_rails_7548887bd0 FOREIGN KEY (invited_by_id) REFERENCES public.admin_users(id);


--
-- Name: automation_executions fk_rails_77842b67af; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_executions
    ADD CONSTRAINT fk_rails_77842b67af FOREIGN KEY (automation_workflow_id) REFERENCES public.automation_workflows(id);


--
-- Name: appointments fk_rails_7e7c23e377; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_rails_7e7c23e377 FOREIGN KEY (habitation_id) REFERENCES public.habitations(id);


--
-- Name: footer_social_links fk_rails_7efc10f336; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.footer_social_links
    ADD CONSTRAINT fk_rails_7efc10f336 FOREIGN KEY (footer_setting_id) REFERENCES public.footer_settings(id);


--
-- Name: account_memberships fk_rails_7f2e532adc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_memberships
    ADD CONSTRAINT fk_rails_7f2e532adc FOREIGN KEY (revoked_by_id) REFERENCES public.admin_users(id);


--
-- Name: admin_users fk_rails_7f39c6a643; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT fk_rails_7f39c6a643 FOREIGN KEY (primary_admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: proposals fk_rails_7f76a65270; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proposals
    ADD CONSTRAINT fk_rails_7f76a65270 FOREIGN KEY (habitation_id) REFERENCES public.habitations(id);


--
-- Name: habitations fk_rails_80a7cb3f5d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitations
    ADD CONSTRAINT fk_rails_80a7cb3f5d FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: lead_property_interests fk_rails_814c4c7079; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_property_interests
    ADD CONSTRAINT fk_rails_814c4c7079 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: notification_template_settings fk_rails_8197357a6f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_template_settings
    ADD CONSTRAINT fk_rails_8197357a6f FOREIGN KEY (whatsapp_template_id) REFERENCES public.whatsapp_templates(id);


--
-- Name: solid_queue_ready_executions fk_rails_81fcbd66af; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions
    ADD CONSTRAINT fk_rails_81fcbd66af FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: crm_appointments fk_rails_822455f468; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_appointments
    ADD CONSTRAINT fk_rails_822455f468 FOREIGN KEY (proprietor_id) REFERENCES public.proprietors(id);


--
-- Name: habitation_broker_assignments fk_rails_837051d439; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_broker_assignments
    ADD CONSTRAINT fk_rails_837051d439 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: automation_workflow_versions fk_rails_8449d535ac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_workflow_versions
    ADD CONSTRAINT fk_rails_8449d535ac FOREIGN KEY (published_by_id) REFERENCES public.admin_users(id);


--
-- Name: profiles fk_rails_8465209026; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT fk_rails_8465209026 FOREIGN KEY (vertical_profile_id) REFERENCES public.profiles(id);


--
-- Name: habitation_interactions fk_rails_8531aa2028; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_interactions
    ADD CONSTRAINT fk_rails_8531aa2028 FOREIGN KEY (crm_contact_id) REFERENCES public.crm_contacts(id);


--
-- Name: automation_workflow_versions fk_rails_861c29bd15; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_workflow_versions
    ADD CONSTRAINT fk_rails_861c29bd15 FOREIGN KEY (automation_workflow_id) REFERENCES public.automation_workflows(id);


--
-- Name: access_control_rules fk_rails_8770e6ed8e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_control_rules
    ADD CONSTRAINT fk_rails_8770e6ed8e FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: access_control_rules fk_rails_891464e92a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_control_rules
    ADD CONSTRAINT fk_rails_891464e92a FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: seo_redirects fk_rails_89614535e7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_redirects
    ADD CONSTRAINT fk_rails_89614535e7 FOREIGN KEY (created_by_admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: distribution_rule_agents fk_rails_89af5b0a07; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.distribution_rule_agents
    ADD CONSTRAINT fk_rails_89af5b0a07 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: account_memberships fk_rails_89ba2cac91; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_memberships
    ADD CONSTRAINT fk_rails_89ba2cac91 FOREIGN KEY (profile_id) REFERENCES public.profiles(id);


--
-- Name: manual_checkin_requests fk_rails_8ae7061d93; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manual_checkin_requests
    ADD CONSTRAINT fk_rails_8ae7061d93 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: whatsapp_campaign_recipients fk_rails_8c063a6839; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_recipients
    ADD CONSTRAINT fk_rails_8c063a6839 FOREIGN KEY (whatsapp_campaign_id) REFERENCES public.whatsapp_campaigns(id);


--
-- Name: whatsapp_campaign_unsubscribes fk_rails_8cdc0b98a2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_unsubscribes
    ADD CONSTRAINT fk_rails_8cdc0b98a2 FOREIGN KEY (whatsapp_sender_number_id) REFERENCES public.whatsapp_sender_numbers(id);


--
-- Name: portal_listing_states fk_rails_8def14d270; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.portal_listing_states
    ADD CONSTRAINT fk_rails_8def14d270 FOREIGN KEY (habitation_id) REFERENCES public.habitations(id);


--
-- Name: manual_checkin_requests fk_rails_90325dd80b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manual_checkin_requests
    ADD CONSTRAINT fk_rails_90325dd80b FOREIGN KEY (reviewed_by_admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: habitation_exports fk_rails_9124ea0acc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_exports
    ADD CONSTRAINT fk_rails_9124ea0acc FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: habitation_interactions fk_rails_91361f264a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_interactions
    ADD CONSTRAINT fk_rails_91361f264a FOREIGN KEY (proprietor_id) REFERENCES public.proprietors(id);


--
-- Name: whatsapp_conversations fk_rails_9151a6c10c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_conversations
    ADD CONSTRAINT fk_rails_9151a6c10c FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: whatsapp_campaigns fk_rails_92b02b457f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaigns
    ADD CONSTRAINT fk_rails_92b02b457f FOREIGN KEY (whatsapp_sender_number_id) REFERENCES public.whatsapp_sender_numbers(id);


--
-- Name: whatsapp_business_integrations fk_rails_92eb1feb23; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_business_integrations
    ADD CONSTRAINT fk_rails_92eb1feb23 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: checkin_audit_logs fk_rails_93113a4461; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checkin_audit_logs
    ADD CONSTRAINT fk_rails_93113a4461 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: footer_stores fk_rails_937ebd4dbd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.footer_stores
    ADD CONSTRAINT fk_rails_937ebd4dbd FOREIGN KEY (footer_setting_id) REFERENCES public.footer_settings(id);


--
-- Name: lead_labelings fk_rails_947f90c152; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_labelings
    ADD CONSTRAINT fk_rails_947f90c152 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: automation_events fk_rails_950cb0d638; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_events
    ADD CONSTRAINT fk_rails_950cb0d638 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: client_property_interests fk_rails_9628964af1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_property_interests
    ADD CONSTRAINT fk_rails_9628964af1 FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: appointments fk_rails_968f2723bc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_rails_968f2723bc FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: habitations fk_rails_97c90c12c7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitations
    ADD CONSTRAINT fk_rails_97c90c12c7 FOREIGN KEY (vista_import_batch_id) REFERENCES public.vista_import_batches(id);


--
-- Name: automation_workflow_versions fk_rails_98bcd5e309; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_workflow_versions
    ADD CONSTRAINT fk_rails_98bcd5e309 FOREIGN KEY (created_by_id) REFERENCES public.admin_users(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: manual_checkin_requests fk_rails_99b1cb9567; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manual_checkin_requests
    ADD CONSTRAINT fk_rails_99b1cb9567 FOREIGN KEY (approved_check_in_id) REFERENCES public.check_ins(id);


--
-- Name: crm_appointments fk_rails_9b331a5646; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_appointments
    ADD CONSTRAINT fk_rails_9b331a5646 FOREIGN KEY (vista_import_batch_id) REFERENCES public.vista_import_batches(id);


--
-- Name: proprietors fk_rails_9c4f41ef47; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proprietors
    ADD CONSTRAINT fk_rails_9c4f41ef47 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: solid_queue_claimed_executions fk_rails_9cfe4d4944; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions
    ADD CONSTRAINT fk_rails_9cfe4d4944 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: account_memberships fk_rails_9de42ef7be; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_memberships
    ADD CONSTRAINT fk_rails_9de42ef7be FOREIGN KEY (rentals_manager_id) REFERENCES public.admin_users(id);


--
-- Name: tasks fk_rails_9df5232373; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_9df5232373 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: crm_contacts fk_rails_a0d5f4035f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_contacts
    ADD CONSTRAINT fk_rails_a0d5f4035f FOREIGN KEY (vista_import_batch_id) REFERENCES public.vista_import_batches(id);


--
-- Name: whatsapp_campaign_messages fk_rails_a1286b45ba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_messages
    ADD CONSTRAINT fk_rails_a1286b45ba FOREIGN KEY (whatsapp_campaign_recipient_id) REFERENCES public.whatsapp_campaign_recipients(id);


--
-- Name: public_navigation_events fk_rails_a13b99eafe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.public_navigation_events
    ADD CONSTRAINT fk_rails_a13b99eafe FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: stores fk_rails_a1a57f3b7c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT fk_rails_a1a57f3b7c FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: whatsapp_campaigns fk_rails_a1f28d7e1b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaigns
    ADD CONSTRAINT fk_rails_a1f28d7e1b FOREIGN KEY (automation_workflow_id) REFERENCES public.automation_workflows(id);


--
-- Name: stores fk_rails_a351b46480; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT fk_rails_a351b46480 FOREIGN KEY (footer_store_id) REFERENCES public.footer_stores(id);


--
-- Name: admin_users fk_rails_a6e17e12bd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT fk_rails_a6e17e12bd FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: habitations fk_rails_b0b092703f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitations
    ADD CONSTRAINT fk_rails_b0b092703f FOREIGN KEY (admin_reviewed_by_id) REFERENCES public.admin_users(id);


--
-- Name: user_meta_integrations fk_rails_b1764c6b36; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_meta_integrations
    ADD CONSTRAINT fk_rails_b1764c6b36 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: automation_events fk_rails_b1cdd6b9ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_events
    ADD CONSTRAINT fk_rails_b1cdd6b9ed FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: whatsapp_campaign_recipients fk_rails_b3ebdb9b63; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_recipients
    ADD CONSTRAINT fk_rails_b3ebdb9b63 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: meta_lead_forms fk_rails_b4b9beb161; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meta_lead_forms
    ADD CONSTRAINT fk_rails_b4b9beb161 FOREIGN KEY (meta_facebook_page_id) REFERENCES public.meta_facebook_pages(id);


--
-- Name: lead_activities fk_rails_b52a6e8f8d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_activities
    ADD CONSTRAINT fk_rails_b52a6e8f8d FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: photography_schedule_blocks fk_rails_b567a6e52d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.photography_schedule_blocks
    ADD CONSTRAINT fk_rails_b567a6e52d FOREIGN KEY (created_by_id) REFERENCES public.admin_users(id);


--
-- Name: user_meta_integrations fk_rails_b94a922717; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_meta_integrations
    ADD CONSTRAINT fk_rails_b94a922717 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: client_property_interests fk_rails_b98e81d5c7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_property_interests
    ADD CONSTRAINT fk_rails_b98e81d5c7 FOREIGN KEY (vista_import_batch_id) REFERENCES public.vista_import_batches(id);


--
-- Name: access_audit_logs fk_rails_ba13076d13; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_audit_logs
    ADD CONSTRAINT fk_rails_ba13076d13 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: manual_checkin_requests fk_rails_ba396e4d85; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manual_checkin_requests
    ADD CONSTRAINT fk_rails_ba396e4d85 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: marketing_campaigns fk_rails_bac0f15c01; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketing_campaigns
    ADD CONSTRAINT fk_rails_bac0f15c01 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: automation_workflows fk_rails_bcad8004e0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_workflows
    ADD CONSTRAINT fk_rails_bcad8004e0 FOREIGN KEY (created_by_id) REFERENCES public.admin_users(id);


--
-- Name: google_calendar_integration_settings fk_rails_bd34034ff6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.google_calendar_integration_settings
    ADD CONSTRAINT fk_rails_bd34034ff6 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: client_property_interests fk_rails_bd88596118; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_property_interests
    ADD CONSTRAINT fk_rails_bd88596118 FOREIGN KEY (proprietor_id) REFERENCES public.proprietors(id);


--
-- Name: whatsapp_campaigns fk_rails_bded8a2aaa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaigns
    ADD CONSTRAINT fk_rails_bded8a2aaa FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: property_settings fk_rails_be2f13cf01; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.property_settings
    ADD CONSTRAINT fk_rails_be2f13cf01 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: trusted_devices fk_rails_c1b334ed72; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trusted_devices
    ADD CONSTRAINT fk_rails_c1b334ed72 FOREIGN KEY (created_by_id) REFERENCES public.admin_users(id);


--
-- Name: seo_conversion_events fk_rails_c272ff638d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_conversion_events
    ADD CONSTRAINT fk_rails_c272ff638d FOREIGN KEY (marketing_campaign_id) REFERENCES public.marketing_campaigns(id);


--
-- Name: check_ins fk_rails_c2a6d4a105; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.check_ins
    ADD CONSTRAINT fk_rails_c2a6d4a105 FOREIGN KEY (store_shift_id) REFERENCES public.store_shifts(id);


--
-- Name: habitation_broker_assignments fk_rails_c366289351; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_broker_assignments
    ADD CONSTRAINT fk_rails_c366289351 FOREIGN KEY (habitation_id) REFERENCES public.habitations(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: habitations fk_rails_c3c5adeb81; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitations
    ADD CONSTRAINT fk_rails_c3c5adeb81 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: access_control_rules fk_rails_c3da571690; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.access_control_rules
    ADD CONSTRAINT fk_rails_c3da571690 FOREIGN KEY (profile_id) REFERENCES public.profiles(id);


--
-- Name: solid_queue_scheduled_executions fk_rails_c4316f352d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions
    ADD CONSTRAINT fk_rails_c4316f352d FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: tasks fk_rails_c4ca39ccc2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_c4ca39ccc2 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: whatsapp_campaign_recipients fk_rails_c55335b620; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_recipients
    ADD CONSTRAINT fk_rails_c55335b620 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: secure_links fk_rails_c574b4468c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.secure_links
    ADD CONSTRAINT fk_rails_c574b4468c FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: automation_execution_steps fk_rails_c5bec9deed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_execution_steps
    ADD CONSTRAINT fk_rails_c5bec9deed FOREIGN KEY (automation_execution_id) REFERENCES public.automation_executions(id);


--
-- Name: vista_raw_records fk_rails_c87e7e92c0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vista_raw_records
    ADD CONSTRAINT fk_rails_c87e7e92c0 FOREIGN KEY (vista_import_batch_id) REFERENCES public.vista_import_batches(id);


--
-- Name: proposals fk_rails_c8aa267acd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.proposals
    ADD CONSTRAINT fk_rails_c8aa267acd FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: automation_executions fk_rails_c96f23d405; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_executions
    ADD CONSTRAINT fk_rails_c96f23d405 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: store_shifts fk_rails_c9e77c3011; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_shifts
    ADD CONSTRAINT fk_rails_c9e77c3011 FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- Name: presentation_cards fk_rails_cb854d1c50; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.presentation_cards
    ADD CONSTRAINT fk_rails_cb854d1c50 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: lead_labels fk_rails_cd877c6e53; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_labels
    ADD CONSTRAINT fk_rails_cd877c6e53 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: automation_rules fk_rails_cf6a0dd51b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_rules
    ADD CONSTRAINT fk_rails_cf6a0dd51b FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: account_memberships fk_rails_d11605f7e1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_memberships
    ADD CONSTRAINT fk_rails_d11605f7e1 FOREIGN KEY (manager_id) REFERENCES public.admin_users(id);


--
-- Name: trusted_devices fk_rails_d44f794038; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trusted_devices
    ADD CONSTRAINT fk_rails_d44f794038 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: distribution_rules fk_rails_d49a5237d1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.distribution_rules
    ADD CONSTRAINT fk_rails_d49a5237d1 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: seo_change_logs fk_rails_d4abca6a38; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_change_logs
    ADD CONSTRAINT fk_rails_d4abca6a38 FOREIGN KEY (seo_setting_id) REFERENCES public.seo_settings(id);


--
-- Name: automation_webhook_deliveries fk_rails_d4def20ddb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_webhook_deliveries
    ADD CONSTRAINT fk_rails_d4def20ddb FOREIGN KEY (automation_event_id) REFERENCES public.automation_events(id);


--
-- Name: automation_runs fk_rails_d4f6870713; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_runs
    ADD CONSTRAINT fk_rails_d4f6870713 FOREIGN KEY (automation_rule_id) REFERENCES public.automation_rules(id);


--
-- Name: crm_appointments fk_rails_d75fe772c7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crm_appointments
    ADD CONSTRAINT fk_rails_d75fe772c7 FOREIGN KEY (habitation_id) REFERENCES public.habitations(id);


--
-- Name: whatsapp_campaign_unsubscribes fk_rails_d85b823492; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_unsubscribes
    ADD CONSTRAINT fk_rails_d85b823492 FOREIGN KEY (whatsapp_campaign_message_id) REFERENCES public.whatsapp_campaign_messages(id);


--
-- Name: seo_conversion_events fk_rails_d8efb77461; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seo_conversion_events
    ADD CONSTRAINT fk_rails_d8efb77461 FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: attribute_options fk_rails_d92fe9ed75; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attribute_options
    ADD CONSTRAINT fk_rails_d92fe9ed75 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: admin_users fk_rails_d966db7d2f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT fk_rails_d966db7d2f FOREIGN KEY (default_store_id) REFERENCES public.stores(id);


--
-- Name: automation_webhook_deliveries fk_rails_d9b086da60; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_webhook_deliveries
    ADD CONSTRAINT fk_rails_d9b086da60 FOREIGN KEY (automation_execution_step_id) REFERENCES public.automation_execution_steps(id);


--
-- Name: habitation_audit_logs fk_rails_da066d1bf0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_audit_logs
    ADD CONSTRAINT fk_rails_da066d1bf0 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: leads fk_rails_da2e88f6a7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT fk_rails_da2e88f6a7 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: whatsapp_messages fk_rails_db315c944a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_messages
    ADD CONSTRAINT fk_rails_db315c944a FOREIGN KEY (whatsapp_conversation_id) REFERENCES public.whatsapp_conversations(id);


--
-- Name: habitation_broker_assignments fk_rails_dc25c47a24; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_broker_assignments
    ADD CONSTRAINT fk_rails_dc25c47a24 FOREIGN KEY (vista_import_batch_id) REFERENCES public.vista_import_batches(id);


--
-- Name: whatsapp_campaign_messages fk_rails_e07384f903; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_messages
    ADD CONSTRAINT fk_rails_e07384f903 FOREIGN KEY (whatsapp_campaign_id) REFERENCES public.whatsapp_campaigns(id);


--
-- Name: admin_users fk_rails_e079e77d29; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT fk_rails_e079e77d29 FOREIGN KEY (horizontal_profile_id) REFERENCES public.profiles(id);


--
-- Name: location_pings fk_rails_e12dc32194; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location_pings
    ADD CONSTRAINT fk_rails_e12dc32194 FOREIGN KEY (check_in_id) REFERENCES public.check_ins(id);


--
-- Name: client_property_interests fk_rails_e2de1e8832; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_property_interests
    ADD CONSTRAINT fk_rails_e2de1e8832 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: whatsapp_conversations fk_rails_e3fd91ed99; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_conversations
    ADD CONSTRAINT fk_rails_e3fd91ed99 FOREIGN KEY (assigned_admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: whatsapp_campaign_messages fk_rails_e477ef2c00; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_messages
    ADD CONSTRAINT fk_rails_e477ef2c00 FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: admin_users fk_rails_e4ce59bd8f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT fk_rails_e4ce59bd8f FOREIGN KEY (manager_id) REFERENCES public.admin_users(id);


--
-- Name: whatsapp_business_integrations fk_rails_e73641bd15; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_business_integrations
    ADD CONSTRAINT fk_rails_e73641bd15 FOREIGN KEY (connected_by_admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: manual_checkin_requests fk_rails_e7ad16aecb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manual_checkin_requests
    ADD CONSTRAINT fk_rails_e7ad16aecb FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- Name: client_interactions fk_rails_e8902714fa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_interactions
    ADD CONSTRAINT fk_rails_e8902714fa FOREIGN KEY (habitation_id) REFERENCES public.habitations(id);


--
-- Name: client_interactions fk_rails_e8a5984373; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_interactions
    ADD CONSTRAINT fk_rails_e8a5984373 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: habitation_interactions fk_rails_e9d6bd4b59; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_interactions
    ADD CONSTRAINT fk_rails_e9d6bd4b59 FOREIGN KEY (vista_import_batch_id) REFERENCES public.vista_import_batches(id);


--
-- Name: whatsapp_campaign_unsubscribes fk_rails_ea5bfea8f5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.whatsapp_campaign_unsubscribes
    ADD CONSTRAINT fk_rails_ea5bfea8f5 FOREIGN KEY (unsubscribed_by_message_id) REFERENCES public.whatsapp_messages(id);


--
-- Name: habitation_interactions fk_rails_ea8d35a43f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_interactions
    ADD CONSTRAINT fk_rails_ea8d35a43f FOREIGN KEY (habitation_id) REFERENCES public.habitations(id);


--
-- Name: tasks fk_rails_ec34c29a53; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_ec34c29a53 FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: automation_execution_steps fk_rails_ec5169344f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_execution_steps
    ADD CONSTRAINT fk_rails_ec5169344f FOREIGN KEY (tenant_id) REFERENCES public.tenants(id);


--
-- Name: distribution_rules fk_rails_ec979d2a3e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.distribution_rules
    ADD CONSTRAINT fk_rails_ec979d2a3e FOREIGN KEY (checkin_store_id) REFERENCES public.stores(id);


--
-- Name: admin_users fk_rails_ecf9739b53; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT fk_rails_ecf9739b53 FOREIGN KEY (vista_import_batch_id) REFERENCES public.vista_import_batches(id);


--
-- Name: lead_activities fk_rails_ee14909c06; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_activities
    ADD CONSTRAINT fk_rails_ee14909c06 FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: automation_executions fk_rails_ef0c0e3b67; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.automation_executions
    ADD CONSTRAINT fk_rails_ef0c0e3b67 FOREIGN KEY (automation_event_id) REFERENCES public.automation_events(id);


--
-- Name: lead_property_interests fk_rails_f209bd58a6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lead_property_interests
    ADD CONSTRAINT fk_rails_f209bd58a6 FOREIGN KEY (lead_id) REFERENCES public.leads(id);


--
-- Name: leads fk_rails_f3159e7558; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT fk_rails_f3159e7558 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: habitation_photo_shares fk_rails_f8257292ce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.habitation_photo_shares
    ADD CONSTRAINT fk_rails_f8257292ce FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: vista_file_assets fk_rails_fdbde1c8b5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vista_file_assets
    ADD CONSTRAINT fk_rails_fdbde1c8b5 FOREIGN KEY (vista_raw_record_id) REFERENCES public.vista_raw_records(id);


--
-- Name: push_delivery_events fk_rails_fdc40cc273; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_delivery_events
    ADD CONSTRAINT fk_rails_fdc40cc273 FOREIGN KEY (push_subscription_id) REFERENCES public.push_subscriptions(id);


--
-- Name: store_shifts fk_rails_fe171d980e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_shifts
    ADD CONSTRAINT fk_rails_fe171d980e FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- Name: push_subscriptions fk_rails_fe18a5fba2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT fk_rails_fe18a5fba2 FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id);


--
-- PostgreSQL database dump complete
--

\unrestrict i2TCI7f7N0AashqeSviLNsiciVEh4MWQYi88yY8ft1vKxQpSWA2MfFDZ2FAMWzn

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260710134500'),
('20260710113000'),
('20260710094500'),
('20260710093000'),
('20260709114600'),
('20260709015000'),
('20260709014500'),
('20260709013000'),
('20260709000009'),
('20260709000008'),
('20260709000007'),
('20260709000006'),
('20260709000005'),
('20260709000004'),
('20260709000003'),
('20260709000002'),
('20260709000001'),
('20260708000007'),
('20260708000006'),
('20260708000005'),
('20260708000004'),
('20260708000003'),
('20260708000002'),
('20260708000001'),
('20260707000002'),
('20260707000001'),
('20260706120000'),
('20260706000007'),
('20260706000006'),
('20260706000005'),
('20260706000004'),
('20260706000003'),
('20260706000002'),
('20260706000001'),
('20260705120000'),
('20260705000011'),
('20260705000010'),
('20260705000009'),
('20260705000008'),
('20260705000007'),
('20260705000006'),
('20260705000005'),
('20260705000004'),
('20260705000003'),
('20260705000002'),
('20260705000001'),
('20260704000006'),
('20260704000005'),
('20260704000004'),
('20260704000003'),
('20260704000002'),
('20260704000001'),
('20260702000010'),
('20260702000009'),
('20260702000008'),
('20260702000007'),
('20260702000006'),
('20260702000005'),
('20260702000004'),
('20260702000003'),
('20260702000002'),
('20260702000001'),
('20260701000002'),
('20260701000001'),
('20260630140000'),
('20260630120000'),
('20260628255000'),
('20260628254500'),
('20260628254400'),
('20260628254300'),
('20260628254200'),
('20260628254100'),
('20260628254000'),
('20260628253000'),
('20260628252000'),
('20260628251000'),
('20260628250000'),
('20260628245000'),
('20260628244000'),
('20260628243000'),
('20260628242000'),
('20260628241000'),
('20260628240000'),
('20260628235900'),
('20260628235800'),
('20260628235700'),
('20260628235600'),
('20260628235500'),
('20260628235000'),
('20260628234000'),
('20260628223000'),
('20260628192500'),
('20260628185000'),
('20260627215000'),
('20260627172000'),
('20260627152000'),
('20260627143000'),
('20260627113000'),
('20260627102000'),
('20260627093200'),
('20260627093100'),
('20260627093000'),
('20260626164000'),
('20260626120200'),
('20260626120100'),
('20260626120000'),
('20260626103000'),
('20260624200000'),
('20260624190000'),
('20260624180000'),
('20260624170000'),
('20260624160000'),
('20260624150000'),
('20260624140000'),
('20260624130100'),
('20260624130000'),
('20260624120000'),
('20260623180000'),
('20260623170100'),
('20260623170000'),
('20260623160000'),
('20260623120000'),
('20260622162257'),
('20260622150000'),
('20260622103000'),
('20260621220500'),
('20260621214500'),
('20260621180514'),
('20260620172000'),
('20260620170000'),
('20260620124000'),
('20260620120000'),
('20260619234000'),
('20260619120000'),
('20260619114704'),
('20260618150000'),
('20260618140000'),
('20260618130000'),
('20260618120000'),
('20260617140000'),
('20260617130000'),
('20260617120000'),
('20260616212000'),
('20260616200000'),
('20260616193000'),
('20260616120000'),
('20260615181000'),
('20260615180000'),
('20260615153000'),
('20260615141453'),
('20260613110200'),
('20260613104600'),
('20260611211000'),
('20260611210000'),
('20260611203000'),
('20260611202000'),
('20260611201000'),
('20260611200000'),
('20260611192000'),
('20260611191000'),
('20260611190000'),
('20260611162000'),
('20260611130000'),
('20260610172000'),
('20260609170000'),
('20260609143000'),
('20260608190000'),
('20260606123000'),
('20260605123358'),
('20260605093000'),
('20260602193000'),
('20260601092500'),
('20260531194000'),
('20260530212000'),
('20260530205000'),
('20260530200000'),
('20260530190000'),
('20260530183000'),
('20260530170000'),
('20260530152000'),
('20260530123000'),
('20260527191000'),
('20260527190500'),
('20260527173158'),
('20260523155636'),
('20260523152839'),
('20260522211000'),
('20260522174500'),
('20260522173500'),
('20260522172700'),
('20260522172600'),
('20260522172500'),
('20260522171512'),
('20260522170618'),
('20260522120000'),
('20260512180000'),
('20260512120000'),
('20260509133000'),
('20260509124500'),
('20260509123000'),
('20260508143000'),
('20260508133000'),
('20260508121500'),
('20260507142000'),
('20260507131000'),
('20260507124000'),
('20260507123000'),
('20260507122000'),
('20260507121000'),
('20260507120000'),
('20260506100000'),
('20260505152000'),
('20260505143000'),
('20260505113000'),
('20260505110000'),
('20260420240000'),
('20260420230000'),
('20260420220001'),
('20260420220000'),
('20260420210000'),
('20260420200000'),
('20260420180000'),
('20260420170000'),
('20260420160000'),
('20260420150000'),
('20260420140000'),
('20260420130000'),
('20260420120000'),
('20260420020000'),
('20260420010000'),
('20260419230000'),
('20260419220000'),
('20260419120000'),
('20260401180500'),
('20260401173500'),
('20260401171000'),
('20260401170000'),
('20260401145500'),
('20260401141200'),
('20260401141100'),
('20260401141000'),
('20260323195000'),
('20260323154500'),
('20260317103100'),
('20260317103000'),
('20260317013500'),
('20260317004500'),
('20260317002000'),
('20260316212000'),
('20260316201000'),
('20260316181000'),
('20260316180000'),
('20260219110000'),
('20260209231500'),
('20260209224000'),
('20260209221000'),
('20260209214000'),
('20260209203000'),
('20260209190000'),
('20260209160804'),
('20260209160803'),
('20260209144202'),
('20260209011909'),
('20260209011821'),
('20260208224237'),
('20260208211941'),
('20260205221756'),
('20260205201505'),
('20260205190553'),
('20260205182455'),
('20260205175616'),
('20260205173935'),
('20260205173934'),
('20260205173933'),
('20260205162648'),
('20260205153508'),
('20260205153343'),
('20260205135413'),
('20260205133839'),
('20260205125516'),
('20260205125515'),
('20260205125514'),
('20260205122955'),
('20260205122807'),
('20260205122634'),
('20260205121042'),
('20260112012254'),
('20260111230258'),
('20260111230256'),
('20260110192156'),
('20260110185519'),
('20260110185210'),
('20260110011550'),
('20260110004530'),
('20260110004529'),
('20260110004527'),
('20260110004526'),
('20260109222214'),
('20260109215741'),
('20260109215740'),
('20260109210957'),
('20260109210040'),
('20260109161448'),
('20260109161447'),
('20260109131432'),
('20251126042444'),
('20251125175442'),
('20251125174440'),
('20251125165431'),
('20251125160808'),
('20251125160807'),
('20251125160805'),
('20251125160804'),
('20251125160425'),
('20251124011442'),
('20251124011439'),
('20251124011435'),
('20251124011430'),
('20251124003706'),
('20251123102600'),
('20251123040000'),
('20251123005900'),
('20251122130154'),
('20251122125348'),
('20251122125042');

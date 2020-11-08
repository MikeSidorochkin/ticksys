CLASS ycl_ticksys_jira DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES yif_addict_ticketing_system.
    CLASS-METHODS class_constructor.
  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES jira_field_list TYPE STANDARD TABLE OF yd_ticksys_jira_field WITH EMPTY KEY.
    TYPES jista_list TYPE STANDARD TABLE OF ytticksys_jista WITH EMPTY KEY.
    TYPES string_range TYPE RANGE OF string.

    TYPES transition_set TYPE HASHED TABLE OF ytticksys_jitra
          WITH UNIQUE KEY primary_key COMPONENTS from_status to_status.

    TYPES: BEGIN OF bin_dict,
             line TYPE x LENGTH 255,
           END OF bin_dict,

           bin_list TYPE STANDARD TABLE OF bin_dict WITH EMPTY KEY.

    TYPES: BEGIN OF custom_field_value_dict,
             jira_field TYPE yd_ticksys_jira_field,
             value      TYPE string,
           END OF custom_field_value_dict,

           custom_field_value_set TYPE HASHED TABLE OF custom_field_value_dict
           WITH UNIQUE KEY primary_key COMPONENTS jira_field.

    TYPES: BEGIN OF jira_cache_dict,
             ticket_id     TYPE ysaddict_ticket_header-ticket_id,
             header        TYPE ysaddict_ticket_header,
             sub_tickets   TYPE yif_addict_ticketing_system=>ticket_id_list,
             custom_fields TYPE custom_field_value_set,
           END OF jira_cache_dict,

           jira_cache_set TYPE HASHED TABLE OF jira_cache_dict
           WITH UNIQUE KEY primary_key COMPONENTS ticket_id.

    CONSTANTS ticsy_id TYPE yd_ticksys_ticsy_id VALUE 'JIRA'.

    CONSTANTS: BEGIN OF http_return,
                 ok TYPE i VALUE 200,
               END OF http_return.

    CONSTANTS: BEGIN OF status_code,
                 ok TYPE char3 VALUE '204',
               END OF status_code.

    CONSTANTS: BEGIN OF table,
                 jira_def         TYPE tabname VALUE 'YTTICKSYS_JIDEF',
                 jira_transitions TYPE tabname VALUE 'YTTICKSYS_JITRA',
               END OF table.

    CONSTANTS: BEGIN OF field,
                 url      TYPE fieldname VALUE 'URL',
                 username TYPE fieldname VALUE 'USERNAME',
                 password TYPE fieldname VALUE 'PASSWORD',
               END OF field.

    CLASS-DATA jira_cache TYPE jira_cache_set.
    CLASS-DATA jira_definitions TYPE ytticksys_jidef.
    CLASS-DATA jira_transitions TYPE transition_set.
    CLASS-DATA jira_status_assignee_fields TYPE jista_list.
    CLASS-DATA subtask_parent_rng TYPE string_range.

    CLASS-METHODS read_jira_definitions RAISING ycx_addict_table_content.

    METHODS create_http_client
      IMPORTING !url               TYPE clike
      RETURNING VALUE(http_client) TYPE REF TO if_http_client
      RAISING   ycx_ticksys_ticketing_system.

    METHODS get_jira_issue
      IMPORTING !ticket_id    TYPE yd_addict_ticket_id
                !bypass_cache TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(output) TYPE jira_cache_dict
      RAISING   ycx_ticksys_ticketing_system
                ycx_addict_table_content.

    METHODS get_assignee_fields_for_status
      IMPORTING !status_id    TYPE yd_addict_ticket_status_id
      RETURNING VALUE(fields) TYPE jira_field_list.
ENDCLASS.



CLASS ycl_ticksys_jira IMPLEMENTATION.
  METHOD class_constructor.
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    " Called upon initial access
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    TRY.
        read_jira_definitions( ).
      CATCH cx_root INTO DATA(diaper).
        MESSAGE diaper TYPE ycl_simbal=>msgty-error.
    ENDTRY.

    ycl_ticksys_jira=>subtask_parent_rng = VALUE #(
        ( sign   = ycl_addict_toolkit=>sign-include
          option = ycl_addict_toolkit=>option-cp
          low    = '/issues/*/fields/subtasks/*' )
        ( sign   = ycl_addict_toolkit=>sign-exclude
          option = ycl_addict_toolkit=>option-cp
          low    = '/issues/*/fields/subtasks/*/*' ) ).
  ENDMETHOD.


  METHOD read_jira_definitions.
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    " Reads & caches Jira based definitions
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    SELECT SINGLE * FROM ytticksys_jidef
           WHERE sysid = @sy-sysid
           INTO CORRESPONDING FIELDS OF @jira_definitions.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE ycx_addict_table_content
        EXPORTING
          textid   = ycx_addict_table_content=>no_entry_for_objectid
          tabname  = ycl_ticksys_jira=>table-jira_def
          objectid = CONV #( sy-sysid ).
    ENDIF.

    IF jira_definitions-url IS INITIAL.
      RAISE EXCEPTION TYPE ycx_addict_table_content
        EXPORTING
          textid    = ycx_addict_table_content=>entry_field_empty
          tabname   = ycl_ticksys_jira=>table-jira_def
          objectid  = CONV #( sy-sysid )
          fieldname = field-url.
    ENDIF.

    IF jira_definitions-username IS INITIAL.
      RAISE EXCEPTION TYPE ycx_addict_table_content
        EXPORTING
          textid    = ycx_addict_table_content=>entry_field_empty
          tabname   = ycl_ticksys_jira=>table-jira_def
          objectid  = CONV #( sy-sysid )
          fieldname = field-username.
    ENDIF.

    IF jira_definitions-password IS INITIAL.
      RAISE EXCEPTION TYPE ycx_addict_table_content
        EXPORTING
          textid    = ycx_addict_table_content=>entry_field_empty
          tabname   = ycl_ticksys_jira=>table-jira_def
          objectid  = CONV #( sy-sysid )
          fieldname = field-password.
    ENDIF.

    SELECT * FROM ytticksys_jitra                       "#EC CI_NOWHERE
             INTO TABLE @ycl_ticksys_jira=>jira_transitions.

    SELECT * FROM ytticksys_jista                       "#EC CI_NOWHERE
             ORDER BY status_id, priority
             INTO TABLE @ycl_ticksys_jira=>jira_status_assignee_fields.
  ENDMETHOD.


  METHOD create_http_client.
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    " Creates a new HTTP client connecting to Jira
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    cl_http_client=>create_by_url(
      EXPORTING url    = CONV #( url )
      IMPORTING client = http_client
      EXCEPTIONS argument_not_found = 1
                 plugin_not_active  = 2
                 internal_error     = 3
                 OTHERS             = 4 ).

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE ycx_ticksys_ticketing_system
        EXPORTING
          textid   = ycx_ticksys_ticketing_system=>http_client_creation_error
          ticsy_id = me->ticsy_id.
    ENDIF.

    http_client->request->set_version( if_http_request=>co_protocol_version_1_0 ).

    http_client->authenticate(
        username = CONV #( me->jira_definitions-username )
        password = CONV #( me->jira_definitions-password ) ).
  ENDMETHOD.


  METHOD get_jira_issue.
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    " Reads the given Jira issue from the server
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    IF bypass_cache = abap_true.
      DELETE me->jira_cache WHERE ticket_id = ticket_id.
    ENDIF.

    ASSIGN me->jira_cache[ KEY primary_key COMPONENTS
                           ticket_id = ticket_id
                         ] TO FIELD-SYMBOL(<cache>).
    IF sy-subrc <> 0.
      DATA(cache) = VALUE jira_cache_dict(
          ticket_id = ticket_id
          header    = VALUE #( ticket_id = ticket_id ) ).

      DATA(url)   = |{ me->jira_definitions-url }/rest/api/2/search|.
      DATA(http_client) = create_http_client( url ).

      http_client->request->set_method( if_http_request=>co_request_method_get ).

      http_client->request->set_form_field(
          name  = 'jql'
          value = |issuekey={ ticket_id }| ).

      " Full list if needed:
      " 'names,renderedFields,schema,transitions,operations,editmeta,changelog'
      http_client->request->set_form_field(
          name  = 'expand'
          value = '' ).

      http_client->request->set_form_field(
          name  = 'maxResults'
          value = '1' ).

      http_client->send(
        EXCEPTIONS http_communication_failure = 1
                   http_invalid_state         = 2
                   http_processing_failed     = 3
                   http_invalid_timeout       = 4
                   OTHERS                     = 5 ).

      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE ycx_ticksys_ticketing_system
          EXPORTING
            textid   = ycx_ticksys_ticketing_system=>http_request_error
            ticsy_id = ycl_ticksys_jira=>ticsy_id.
      ENDIF.

      http_client->receive(
        EXCEPTIONS http_communication_failure = 1
                   http_invalid_state         = 2
                   http_processing_failed     = 3
                   OTHERS                     = 4 ).

      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE ycx_ticksys_ticketing_system
          EXPORTING
            textid   = ycx_ticksys_ticketing_system=>http_response_error
            ticsy_id = ycl_ticksys_jira=>ticsy_id.
      ENDIF.

      http_client->response->get_status( IMPORTING code = DATA(rc) ).
      DATA(response) = http_client->response->get_data( ).
      http_client->close( ).

      IF rc <> me->http_return-ok.
        RAISE EXCEPTION TYPE ycx_ticksys_ticketing_system
          EXPORTING
            textid   = ycx_ticksys_ticketing_system=>http_responded_with_error
            ticsy_id = ycl_ticksys_jira=>ticsy_id.
      ENDIF.

      DATA(len) = 0.
      DATA(bin) = VALUE bin_list( ).

      CALL FUNCTION 'SCMS_XSTRING_TO_BINARY'
        EXPORTING
          buffer        = response
        IMPORTING
          output_length = len
        TABLES
          binary_tab    = bin.

      DATA(json_response) = CONV string( space ).

      CALL FUNCTION 'SCMS_BINARY_TO_STRING'
        EXPORTING
          input_length = len
        IMPORTING
          text_buffer  = json_response
        TABLES
          binary_tab   = bin
        EXCEPTIONS
          failed       = 1
          OTHERS       = 2.

      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE ycx_ticksys_ticketing_system
          EXPORTING
            textid   = ycx_ticksys_ticketing_system=>http_response_parse_error
            ticsy_id = ycl_ticksys_jira=>ticsy_id.
      ENDIF.

      DATA(parser) = NEW /ui5/cl_json_parser( ).
      parser->parse( json_response ).

      cache-header-status_id = VALUE #( parser->m_entries[
          parent = '/issues/1/fields/status'
          name   = 'id' ]-value OPTIONAL ).

      cache-header-status_text = VALUE #( parser->m_entries[
          parent = '/issues/1/fields/status'
          name   = 'name' ]-value OPTIONAL ).

      cache-header-completed = xsdbool(
          VALUE string( parser->m_entries[
                        parent = '/issues/1/fields/status/statusCategory'
                        name   = 'key' ]-value OPTIONAL
                      ) = 'done' ).

      cache-header-parent_ticket_id = VALUE #( parser->m_entries[
          parent = '/issues/1/fields/parent'
          name   = 'key' ]-value OPTIONAL ).

      cache-header-type_id = VALUE #( parser->m_entries[
          parent = '/issues/1/fields/issuetype'
          name   = 'id' ]-value OPTIONAL ).

      cache-header-type_text = VALUE #( parser->m_entries[
          parent = '/issues/1/fields/issuetype'
          name   = 'name' ]-value OPTIONAL ).

      cache-sub_tickets = VALUE #(                      "#EC CI_SORTSEQ
          FOR _entry IN parser->m_entries
          WHERE ( parent IN me->subtask_parent_rng AND
                  name = 'key' )
          ( CONV #( _entry-value ) ) ).

      LOOP AT me->jira_status_assignee_fields
              INTO DATA(_jsaf)
              GROUP BY ( jira_field = _jsaf-jira_field )
              ASSIGNING FIELD-SYMBOL(<jsaf>).

        ASSIGN parser->m_entries[
                 parent = |/issues/1/fields/{ <jsaf>-jira_field }|
                 name   = 'name'
               ] TO FIELD-SYMBOL(<custom_field>).

        CHECK sy-subrc = 0.

        INSERT VALUE custom_field_value_dict(
                 jira_field = <jsaf>-jira_field
                 value      = <custom_field>-value
               ) INTO TABLE cache-custom_fields.
      ENDLOOP.

      INSERT cache INTO TABLE me->jira_cache ASSIGNING <cache>.
    ENDIF.

    output = <cache>.
  ENDMETHOD.


  METHOD get_assignee_fields_for_status.
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    " Returns assignee fields for the given status
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    APPEND LINES OF VALUE ycl_ticksys_jira=>jira_field_list(
             FOR _jsaf IN me->jira_status_assignee_fields
             WHERE ( status_id = status_id )
             ( _jsaf-jira_field )
           ) TO fields.

    APPEND LINES OF VALUE ycl_ticksys_jira=>jira_field_list(
             FOR _jsaf IN me->jira_status_assignee_fields
             WHERE ( status_id = space )
             ( _jsaf-jira_field )
           ) TO fields.
  ENDMETHOD.


  METHOD yif_addict_ticketing_system~is_ticket_id_valid.
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    " Checks if the ticket exists in the system
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    TRY.
        get_jira_issue( ticket_id ).
        output = abap_true.
      CATCH cx_root.
        output = abap_false.
    ENDTRY.
  ENDMETHOD.


  METHOD yif_addict_ticketing_system~get_ticket_header.
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    " Returns the header of the ticket
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    TRY.
        output = get_jira_issue( ticket_id )-header.

      CATCH ycx_ticksys_ticketing_system INTO DATA(ts_error).
        RAISE EXCEPTION ts_error.
      CATCH cx_root INTO DATA(diaper).
        RAISE EXCEPTION TYPE ycx_ticksys_ticketing_system
          EXPORTING
            previous = diaper.
    ENDTRY.
  ENDMETHOD.


  METHOD yif_addict_ticketing_system~get_sub_tickets.
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    " Returns the sub-tickets of the given ticket
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    TRY.
        children = get_jira_issue( parent )-sub_tickets.

      CATCH ycx_ticksys_ticketing_system INTO DATA(ts_error).
        RAISE EXCEPTION ts_error.
      CATCH cx_root INTO DATA(diaper).
        RAISE EXCEPTION TYPE ycx_ticksys_ticketing_system
          EXPORTING
            previous = diaper.
    ENDTRY.
  ENDMETHOD.


  METHOD yif_addict_ticketing_system~set_ticket_status.
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    " Sets the status of the ticket
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    TRY.
        " Create HTTP client """"""""""""""""""""""""""""""""""""""""
        DATA(url) = |{ me->jira_definitions-url }/rest/api/2/issue/{ ticket_id }/transitions|.
        DATA(http_client) = create_http_client( url ).

        " Create body """""""""""""""""""""""""""""""""""""""""""""""
        DATA(current_status) = get_jira_issue(
            ticket_id    = ticket_id
            bypass_cache = abap_true )-header-status_id.

        TRY.
            DATA(transition) = REF #( me->jira_transitions[
                               KEY primary_key COMPONENTS
                               from_status = current_status
                               to_status   = status_id ] ).

          CATCH cx_sy_itab_line_not_found INTO DATA(itab_error).
            RAISE EXCEPTION TYPE ycx_addict_table_content
              EXPORTING
                textid   = ycx_addict_table_content=>no_entry_for_objectid
                previous = itab_error
                tabname  = table-jira_transitions
                objectid = |{ current_status }-{ status_id }|.
        ENDTRY.

        DATA(body) = |\{"transition":\{"id":"{ transition->transition_id }"\}\}|.
        DATA(rest_client) = NEW cl_rest_http_client( http_client ).

        DATA(request) = rest_client->if_rest_client~create_request_entity( ).
        request->set_content_type( iv_media_type = if_rest_media_type=>gc_appl_json ).
        request->set_string_data( body ).

        rest_client->if_rest_resource~post( request ).

        DATA(response) = rest_client->if_rest_client~get_response_entity( ).
        DATA(http_code) = response->get_header_field( '~status_code' ).

        IF http_code <> status_code-ok.
          RAISE EXCEPTION TYPE ycx_ticksys_ticketing_system
            EXPORTING
              textid    = ycx_ticksys_ticketing_system=>status_update_error
              ticsy_id  = me->ticsy_id
              ticket_id = ticket_id
              status_id = status_id.
        ENDIF.

      CATCH ycx_ticksys_ticketing_system INTO DATA(ts_error).
        RAISE EXCEPTION ts_error.
      CATCH cx_root INTO DATA(diaper).
        RAISE EXCEPTION TYPE ycx_ticksys_ticketing_system
          EXPORTING
            previous = diaper.
    ENDTRY.
  ENDMETHOD.


  METHOD yif_addict_ticketing_system~set_ticket_assignee.
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    " Sets the ticket assignee
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    TRY.
        DATA(url) = |{ me->jira_definitions-url }/rest/api/2/issue/{ ticket_id }|.
        DATA(http_client) = create_http_client( url ).

        DATA(body) = |\{"fields":\{"assignee":\{"name":"{ assignee }"\}\}\}|.
        DATA(rest_client) = NEW cl_rest_http_client( http_client ).

        DATA(request) = rest_client->if_rest_client~create_request_entity( ).
        request->set_content_type( iv_media_type = if_rest_media_type=>gc_appl_json ).
        request->set_string_data( body ).

        rest_client->if_rest_resource~put( request ).

        DATA(response) = rest_client->if_rest_client~get_response_entity( ).
        DATA(http_code) = response->get_header_field( '~status_code' ).

        IF http_code <> me->status_code-ok.
          RAISE EXCEPTION TYPE ycx_ticksys_assignee_update
            EXPORTING
              ticket_id = ticket_id.
        ENDIF.

      CATCH ycx_ticksys_assignee_update INTO DATA(status_error).
        RAISE EXCEPTION status_error.
      CATCH cx_root INTO DATA(diaper).
        RAISE EXCEPTION TYPE ycx_ticksys_assignee_update
          EXPORTING
            ticket_id = ticket_id
            previous  = diaper.
    ENDTRY.
  ENDMETHOD.


  METHOD yif_addict_ticketing_system~set_ticket_assignee_for_status.
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    " Sets the ticket assignee which corresponds to the provided status
    """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
    TRY.
        DATA(ticket) = get_jira_issue( ticket_id ).
        DATA(field_candidates) = get_assignee_fields_for_status( status_id ).

        LOOP AT field_candidates ASSIGNING FIELD-SYMBOL(<field>).
          ASSIGN ticket-custom_fields[
                   KEY primary_key COMPONENTS
                   jira_field = <field>
                 ] TO FIELD-SYMBOL(<custom_field>).

          CHECK sy-subrc = 0 AND <custom_field>-value IS NOT INITIAL.

          yif_addict_ticketing_system~set_ticket_assignee(
              ticket_id = ticket_id
              assignee  = <custom_field>-value ).

          RETURN.
        ENDLOOP.

        RAISE EXCEPTION TYPE ycx_ticksys_assignee_update
          EXPORTING
            textid    = ycx_ticksys_assignee_update=>new_assignee_not_found
            ticket_id = ticket_id.

      CATCH ycx_ticksys_assignee_update INTO DATA(status_error).
        RAISE EXCEPTION status_error.
      CATCH cx_root INTO DATA(diaper).
        RAISE EXCEPTION TYPE ycx_ticksys_assignee_update
          EXPORTING
            ticket_id = ticket_id
            previous  = diaper.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

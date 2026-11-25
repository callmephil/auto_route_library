import 'package:integration_test/integration_test.dart';

import 'active_guard_observer_test.dart' as active_guard_observer;
import 'active_tab_removed_test.dart' as active_tab_removed;
import 'ancestor_path_params_test.dart' as ancestor_path_params;
import 'android_back_in_app_test.dart' as android_back_in_app;
import 'app_call_into_unopened_tab_waits_test.dart'
    as app_call_into_unopened_tab_waits;
import 'app_smoke_test.dart' as app_smoke;
import 'app_tab_change_waits_for_nested_guards_test.dart'
    as app_tab_change_waits_for_nested_guards;
import 'async_simple_guard_test.dart' as async_simple_guard;
import 'back_after_closing_nested_router_page_test.dart'
    as back_after_closing_nested_router_page;
import 'back_after_closing_unbuilt_page_test.dart'
    as back_after_closing_unbuilt_page;
import 'back_after_link_page_removed_test.dart' as back_after_link_page_removed;
import 'back_after_link_to_other_tab_test.dart' as back_after_link_to_other_tab;
import 'back_after_navigations_in_one_turn_test.dart'
    as back_after_navigations_in_one_turn;
import 'back_after_opening_nested_pages_together_test.dart'
    as back_after_opening_nested_pages_together;
import 'back_after_opening_pages_together_in_tabs_test.dart'
    as back_after_opening_pages_together_in_tabs;
import 'back_after_pages_opened_together_test.dart'
    as back_after_pages_opened_together;
import 'back_after_push_all_in_hidden_tab_test.dart'
    as back_after_push_all_in_hidden_tab;
import 'back_after_push_all_test.dart' as back_after_push_all;
import 'back_after_refused_navigation_test.dart'
    as back_after_refused_navigation;
import 'back_after_reload_test.dart' as back_after_reload;
import 'back_after_remove_until_in_hidden_tab_test.dart'
    as back_after_remove_until_in_hidden_tab;
import 'back_after_removing_link_page_test.dart'
    as back_after_removing_link_page;
import 'back_after_sign_in_test.dart' as back_after_sign_in;
import 'back_after_tab_change_with_waiting_guard_test.dart'
    as back_after_tab_change_with_waiting_guard;
import 'back_in_declarative_router_test.dart' as back_in_declarative_router;
import 'back_in_tabs_test.dart' as back_in_tabs;
import 'back_into_other_tab_asks_only_tab_guards_test.dart'
    as back_into_other_tab_asks_only_tab_guards;
import 'back_into_tab_with_sign_in_redirect_test.dart'
    as back_into_tab_with_sign_in_redirect;
import 'back_into_waiting_tab_guard_test.dart' as back_into_waiting_tab_guard;
import 'back_leaves_waiting_link_test.dart' as back_leaves_waiting_link;
import 'back_rejected_by_guard_test.dart' as back_rejected_by_guard;
import 'back_same_route_params_test.dart' as back_same_route_params;
import 'back_same_url_test.dart' as back_same_url;
import 'back_skips_removed_page_test.dart' as back_skips_removed_page;
import 'back_through_every_open_page_test.dart' as back_through_every_open_page;
import 'back_to_open_page_asks_no_guard_test.dart'
    as back_to_open_page_asks_no_guard;
import 'back_to_shell_home_test.dart' as back_to_shell_home;
import 'back_twice_in_one_turn_test.dart' as back_twice_in_one_turn;
import 'back_twice_test.dart' as back_twice;
import 'back_while_nested_guard_waits_test.dart'
    as back_while_nested_guard_waits;
import 'batch_rejected_keeps_caller_test.dart' as batch_rejected_keeps_caller;
import 'batch_rejected_keeps_stack_test.dart' as batch_rejected_keeps_stack;
import 'batch_slow_guard_test.dart' as batch_slow_guard;
import 'bool_query_param_test.dart' as bool_query_param;
import 'browser_back_to_open_page_asks_no_guard_test.dart'
    as browser_back_to_open_page_asks_no_guard;
import 'callback_guard_stale_yes_test.dart' as callback_guard_stale_yes;
import 'camel_case_path_test.dart' as camel_case_path;
import 'change_during_guard_check_test.dart' as change_during_guard_check;
import 'change_during_navigation_guard_test.dart'
    as change_during_navigation_guard;
import 'change_in_later_round_test.dart' as change_in_later_round;
import 'child_route_fragment_test.dart' as child_route_fragment;
import 'closed_tabs_end_held_tab_test.dart' as closed_tabs_end_held_tab;
import 'covered_window_test.dart' as covered_window;
import 'cupertino_page_pop_scope_with_drawer_test.dart'
    as cupertino_page_pop_scope_with_drawer;
import 'cupertino_title_after_page_update_test.dart'
    as cupertino_title_after_page_update;
import 'current_hierarchy_test.dart' as current_hierarchy;
import 'current_url_test.dart' as current_url;
import 'custom_route_barrier_dismissible_test.dart'
    as custom_route_barrier_dismissible;
import 'custom_route_current_result_test.dart' as custom_route_current_result;
import 'custom_route_query_params_test.dart' as custom_route_query_params;
import 'custom_route_swipe_back_test.dart' as custom_route_swipe_back;
import 'custom_route_transition_test.dart' as custom_route_transition;
import 'custom_route_underneath_test.dart' as custom_route_underneath;
import 'declarative_hero_controller_test.dart' as declarative_hero_controller;
import 'declarative_initial_routes_test.dart' as declarative_initial_routes;
import 'declarative_leading_button_after_pop_test.dart'
    as declarative_leading_button_after_pop;
import 'declarative_on_navigate_once_test.dart' as declarative_on_navigate_once;
import 'declarative_popped_page_still_listed_test.dart'
    as declarative_popped_page_still_listed;
import 'declarative_push_message_test.dart' as declarative_push_message;
import 'declarative_router_key_test.dart' as declarative_router_key;
import 'declarative_router_of_test.dart' as declarative_router_of;
import 'declarative_routes_update_test.dart' as declarative_routes_update;
import 'declarative_update_keeps_nested_router_test.dart'
    as declarative_update_keeps_nested_router;
import 'deep_link_parent_build_test.dart' as deep_link_parent_build;
import 'deferred_and_eager_page_test.dart' as deferred_and_eager_page;
import 'deferred_page_failed_load_retry_test.dart'
    as deferred_page_failed_load_retry;
import 'deferred_page_popped_test.dart' as deferred_page_popped;
import 'deferred_widget_own_placeholder_test.dart'
    as deferred_widget_own_placeholder;
import 'dialog_args_route_information_test.dart'
    as dialog_args_route_information;
import 'dialog_then_page_animates_test.dart' as dialog_then_page_animates;
import 'dialog_then_page_pop_test.dart' as dialog_then_page_pop;
import 'disposed_nested_router_test.dart' as disposed_nested_router;
import 'dollar_names_test.dart' as dollar_names;
import 'dropped_tab_without_initial_child_test.dart'
    as dropped_tab_without_initial_child;
import 'duplicate_path_test.dart' as duplicate_path;
import 'eager_tabs_test.dart' as eager_tabs;
import 'empty_list_query_param_test.dart' as empty_list_query_param;
import 'empty_nested_router_test.dart' as empty_nested_router;
import 'empty_query_value_test.dart' as empty_query_value;
import 'encoded_deep_link_test.dart' as encoded_deep_link;
import 'encoded_link_back_test.dart' as encoded_link_back;
import 'encoded_path_params_test.dart' as encoded_path_params;
import 'encoded_url_test.dart' as encoded_url;
import 'enum_query_param_test.dart' as enum_query_param;
import 'forward_after_tabs_page_closes_test.dart'
    as forward_after_tabs_page_closes;
import 'forward_jump_opens_passed_pages_test.dart'
    as forward_jump_opens_passed_pages;
import 'forward_with_sign_in_redirect_test.dart'
    as forward_with_sign_in_redirect;
import 'fragment_question_mark_url_test.dart' as fragment_question_mark_url;
import 'full_url_nested_path_test.dart' as full_url_nested_path;
import 'generic_page_test.dart' as generic_page;
import 'guard_answers_at_once_test.dart' as guard_answers_at_once;
import 'guard_answers_each_call_test.dart' as guard_answers_each_call;
import 'guard_lets_go_keeps_router_test.dart' as guard_lets_go_keeps_router;
import 'guard_throws_tab_test.dart' as guard_throws_tab;
import 'guard_throws_test.dart' as guard_throws;
import 'guarded_tab_link_after_tabs_left_test.dart'
    as guarded_tab_link_after_tabs_left;
import 'held_back_page_after_rebuild_test.dart' as held_back_page_after_rebuild;
import 'held_back_page_leaves_screen_test.dart' as held_back_page_leaves_screen;
import 'held_page_guard_error_test.dart' as held_page_guard_error;
import 'hero_controller_builder_test.dart' as hero_controller_builder;
import 'hero_nested_router_test.dart' as hero_nested_router;
import 'home_index_back_test.dart' as home_index_back;
import 'home_index_update_test.dart' as home_index_update;
import 'host_back_button_test.dart' as host_back_button;
import 'hot_reload_routes_test.dart' as hot_reload_routes;
import 'indexed_stack_curved_animation_test.dart'
    as indexed_stack_curved_animation;
import 'inherited_id_child_test.dart' as inherited_id_child;
import 'inherited_order_id_test.dart' as inherited_order_id;
import 'insert_under_no_history_top_test.dart' as insert_under_no_history_top;
import 'invalid_utf8_escape_link_test.dart' as invalid_utf8_escape_link;
import 'keep_history_test.dart' as keep_history;
import 'late_router_deep_link_test.dart' as late_router_deep_link;
import 'leading_button_drawer_test.dart' as leading_button_drawer;
import 'leading_button_nested_page_removed_test.dart'
    as leading_button_nested_page_removed;
import 'leading_button_nested_pageless_route_test.dart'
    as leading_button_nested_pageless_route;
import 'leading_button_pop_test.dart' as leading_button_pop;
import 'let_go_navigate_one_copy_test.dart' as let_go_navigate_one_copy;
import 'let_go_only_page_above_test.dart' as let_go_only_page_above;
import 'let_go_only_page_test.dart' as let_go_only_page;
import 'let_go_page_above_test.dart' as let_go_page_above;
import 'let_go_push_other_args_test.dart' as let_go_push_other_args;
import 'let_go_redirect_cancel_test.dart' as let_go_redirect_cancel;
import 'let_go_stale_yes_test.dart' as let_go_stale_yes;
import 'link_after_route_without_page_test.dart'
    as link_after_route_without_page;
import 'link_during_initial_guard_test.dart' as link_during_initial_guard;
import 'link_into_eager_tab_with_waiting_guard_test.dart'
    as link_into_eager_tab_with_waiting_guard;
import 'link_into_open_tabs_page_test.dart' as link_into_open_tabs_page;
import 'link_to_guarded_page_in_waiting_tab_test.dart'
    as link_to_guarded_page_in_waiting_tab;
import 'link_to_removed_tab_test.dart' as link_to_removed_tab;
import 'link_url_while_guard_decides_test.dart' as link_url_while_guard_decides;
import 'list_query_param_test.dart' as list_query_param;
import 'listener_asks_for_waiting_tab_test.dart'
    as listener_asks_for_waiting_tab;
import 'login_state_test.dart' as login_state;
import 'logout_redirect_back_test.dart' as logout_redirect_back;
import 'maybe_pop_over_nested_router_in_one_turn_test.dart'
    as maybe_pop_over_nested_router_in_one_turn;
import 'moved_router_keeps_pages_test.dart' as moved_router_keeps_pages;
import 'navigate_absolute_path_test.dart' as navigate_absolute_path;
import 'navigate_after_dialog_test.dart' as navigate_after_dialog;
import 'navigate_awaits_test.dart' as navigate_awaits;
import 'navigate_inherited_path_params_test.dart'
    as navigate_inherited_path_params;
import 'navigate_into_open_page_keeps_dialog_test.dart'
    as navigate_into_open_page_keeps_dialog;
import 'navigate_nested_update_test.dart' as navigate_nested_update;
import 'navigate_open_shell_no_children_test.dart'
    as navigate_open_shell_no_children;
import 'navigate_over_pageless_route_test.dart' as navigate_over_pageless_route;
import 'navigate_reaches_nested_router_in_call_test.dart'
    as navigate_reaches_nested_router_in_call;
import 'navigate_rejected_keeps_stack_test.dart'
    as navigate_rejected_keeps_stack;
import 'navigate_root_from_nested_test.dart' as navigate_root_from_nested;
import 'navigate_to_active_tab_while_guard_decides_test.dart'
    as navigate_to_active_tab_while_guard_decides;
import 'navigate_to_non_tab_test.dart' as navigate_to_non_tab;
import 'navigate_to_unlisted_page_in_unopened_tab_test.dart'
    as navigate_to_unlisted_page_in_unopened_tab;
import 'navigate_to_unshown_tab_keeps_children_test.dart'
    as navigate_to_unshown_tab_keeps_children;
import 'navigation_closes_held_page_test.dart' as navigation_closes_held_page;
import 'navigation_into_tab_waits_for_nested_guards_test.dart'
    as navigation_into_tab_waits_for_nested_guards;
import 'navigations_in_one_turn_test.dart' as navigations_in_one_turn;
import 'nested_absolute_redirect_test.dart' as nested_absolute_redirect;
import 'nested_back_test.dart' as nested_back;
import 'nested_browser_back_test.dart' as nested_browser_back;
import 'nested_did_pop_test.dart' as nested_did_pop;
import 'nested_generated_path_url_test.dart' as nested_generated_path_url;
import 'nested_pop_scope_first_page_test.dart' as nested_pop_scope_first_page;
import 'nested_pop_scope_step_test.dart' as nested_pop_scope_step;
import 'nested_redirect_before_wildcard_test.dart'
    as nested_redirect_before_wildcard;
import 'nested_redirect_shorter_path_test.dart' as nested_redirect_shorter_path;
import 'nested_result_test.dart' as nested_result;
import 'nested_route_aware_test.dart' as nested_route_aware;
import 'nested_route_fragment_test.dart' as nested_route_fragment;
import 'nested_router_semantics_test.dart' as nested_router_semantics;
import 'nested_router_text_field_focus_test.dart'
    as nested_router_text_field_focus;
import 'nested_shell_back_test.dart' as nested_shell_back;
import 'nested_tab_bar_reevaluation_test.dart' as nested_tab_bar_reevaluation;
import 'non_ascii_url_test.dart' as non_ascii_url;
import 'opened_at_rewritten_url_test.dart' as opened_at_rewritten_url;
import 'opened_at_tab_with_waiting_guard_test.dart'
    as opened_at_tab_with_waiting_guard;
import 'optional_args_on_back_test.dart' as optional_args_on_back;
import 'overlapping_reevaluation_test.dart' as overlapping_reevaluation;
import 'override_args_on_reevaluate_test.dart' as override_args_on_reevaluate;
import 'override_children_on_reevaluate_test.dart'
    as override_children_on_reevaluate;
import 'page_semantics_identifier_test.dart' as page_semantics_identifier;
import 'page_taken_off_while_reevaluating_test.dart'
    as page_taken_off_while_reevaluating;
import 'page_view_fast_guard_swipe_test.dart' as page_view_fast_guard_swipe;
import 'page_view_quick_tab_changes_test.dart' as page_view_quick_tab_changes;
import 'page_view_second_swipe_guard_test.dart' as page_view_second_swipe_guard;
import 'page_view_swipe_back_test.dart' as page_view_swipe_back;
import 'page_view_tabs_under_cover_test.dart' as page_view_tabs_under_cover;
import 'page_view_zero_duration_test.dart' as page_view_zero_duration;
import 'pageless_push_rebuild_test.dart' as pageless_push_rebuild;
import 'pages_above_rejected_page_removed_test.dart'
    as pages_above_rejected_page_removed;
import 'pages_over_open_page_wait_for_nested_guards_test.dart'
    as pages_over_open_page_wait_for_nested_guards;
import 'param_converter_test.dart' as param_converter;
import 'parent_pages_build_test.dart' as parent_pages_build;
import 'path_key_link_then_navigate_test.dart' as path_key_link_then_navigate;
import 'path_state_after_replace_test.dart' as path_state_after_replace;
import 'path_state_browser_back_test.dart' as path_state_browser_back;
import 'platform_link_over_launch_page_test.dart'
    as platform_link_over_launch_page;
import 'pop_after_removal_at_frame_end_test.dart'
    as pop_after_removal_at_frame_end;
import 'pop_after_replace_in_one_turn_test.dart'
    as pop_after_replace_in_one_turn;
import 'pop_and_back_test.dart' as pop_and_back;
import 'pop_and_push_all_test.dart' as pop_and_push_all;
import 'pop_and_push_browser_back_test.dart' as pop_and_push_browser_back;
import 'pop_and_push_from_animating_modal_test.dart'
    as pop_and_push_from_animating_modal;
import 'pop_push_pop_test.dart' as pop_push_pop;
import 'pop_right_after_push_test.dart' as pop_right_after_push;
import 'pop_scope_once_test.dart' as pop_scope_once;
import 'pop_scope_test.dart' as pop_scope;
import 'pop_until_back_history_test.dart' as pop_until_back_history;
import 'pop_until_before_build_test.dart' as pop_until_before_build;
import 'pop_until_browser_back_test.dart' as pop_until_browser_back;
import 'pop_until_hides_middle_test.dart' as pop_until_hides_middle;
import 'pop_until_missing_route_test.dart' as pop_until_missing_route;
import 'pop_until_path_then_push_in_one_turn_test.dart'
    as pop_until_path_then_push_in_one_turn;
import 'pop_until_then_push_in_one_turn_test.dart'
    as pop_until_then_push_in_one_turn;
import 'pop_while_held_back_test.dart' as pop_while_held_back;
import 'pop_while_reevaluating_test.dart' as pop_while_reevaluating;
import 'popped_args_released_test.dart' as popped_args_released;
import 'predictive_back_nested_under_root_test.dart'
    as predictive_back_nested_under_root;
import 'prefix_matches_nested_test.dart' as prefix_matches_nested;
import 'prefix_matches_tabs_test.dart' as prefix_matches_tabs;
import 'prefix_stripper_test.dart' as prefix_stripper;
import 'push_all_nested_routes_test.dart' as push_all_nested_routes;
import 'push_all_waits_for_guard_test.dart' as push_all_waits_for_guard;
import 'push_and_pop_until_async_test.dart' as push_and_pop_until_async;
import 'push_and_pop_until_flash_test.dart' as push_and_pop_until_flash;
import 'push_and_pop_until_into_tabs_page_test.dart'
    as push_and_pop_until_into_tabs_page;
import 'push_and_pop_until_test.dart' as push_and_pop_until;
import 'push_and_pop_until_with_name_in_one_turn_test.dart'
    as push_and_pop_until_with_name_in_one_turn;
import 'push_and_reevaluate_test.dart' as push_and_reevaluate;
import 'push_futures_test.dart' as push_futures;
import 'push_into_nested_guard_takes_page_back_test.dart'
    as push_into_nested_guard_takes_page_back;
import 'push_same_route_twice_test.dart' as push_same_route_twice;
import 'push_then_replace_test.dart' as push_then_replace;
import 'push_to_tab_with_waiting_guard_test.dart'
    as push_to_tab_with_waiting_guard;
import 'push_unknown_relative_path_test.dart' as push_unknown_relative_path;
import 'query_param_rebuild_test.dart' as query_param_rebuild;
import 'query_params_on_pop_test.dart' as query_params_on_pop;
import 'query_toggle_back_test.dart' as query_toggle_back;
import 'rapid_pops_test.dart' as rapid_pops;
import 'rebuild_stack_back_and_forward_test.dart'
    as rebuild_stack_back_and_forward;
import 'rebuild_stack_rejected_link_test.dart' as rebuild_stack_rejected_link;
import 'redirect_cycle_test.dart' as redirect_cycle;
import 'redirect_fragment_test.dart' as redirect_fragment;
import 'redirect_history_test.dart' as redirect_history;
import 'redirect_in_closed_nested_router_test.dart'
    as redirect_in_closed_nested_router;
import 'redirect_lifecycle_test.dart' as redirect_lifecycle;
import 'redirect_loop_test.dart' as redirect_loop;
import 'redirect_param_name_prefix_test.dart' as redirect_param_name_prefix;
import 'redirect_partly_matched_target_test.dart'
    as redirect_partly_matched_target;
import 'redirect_path_param_test.dart' as redirect_path_param;
import 'redirect_replace_rejected_test.dart' as redirect_replace_rejected;
import 'redirect_route_cycle_test.dart' as redirect_route_cycle;
import 'redirect_target_colon_test.dart' as redirect_target_colon;
import 'reevaluate_asks_active_tab_guards_test.dart'
    as reevaluate_asks_active_tab_guards;
import 'reevaluate_covered_nested_router_test.dart'
    as reevaluate_covered_nested_router;
import 'reevaluate_deep_link_test.dart' as reevaluate_deep_link;
import 'reevaluate_guarded_tab_child_test.dart' as reevaluate_guarded_tab_child;
import 'reevaluate_slow_guard_rebuild_test.dart'
    as reevaluate_slow_guard_rebuild;
import 'reevaluation_nested_tabs_test.dart' as reevaluation_nested_tabs;
import 'reevaluation_redirect_test.dart' as reevaluation_redirect;
import 'reject_go_back_link_keeps_stack_test.dart'
    as reject_go_back_link_keeps_stack;
import 'rejected_child_of_unbuilt_nested_router_test.dart'
    as rejected_child_of_unbuilt_nested_router;
import 'rejected_initial_link_url_test.dart' as rejected_initial_link_url;
import 'rejected_launch_guarded_first_page_test.dart'
    as rejected_launch_guarded_first_page;
import 'rejected_launch_shows_first_page_test.dart'
    as rejected_launch_shows_first_page;
import 'rejected_link_into_other_tab_test.dart' as rejected_link_into_other_tab;
import 'rejected_link_keeps_dialog_test.dart' as rejected_link_keeps_dialog;
import 'rejected_link_keeps_earlier_link_test.dart'
    as rejected_link_keeps_earlier_link;
import 'rejected_link_url_running_test.dart' as rejected_link_url_running;
import 'rejected_nested_guard_keeps_pages_closing_test.dart'
    as rejected_nested_guard_keeps_pages_closing;
import 'rejected_nested_guard_takes_page_back_test.dart'
    as rejected_nested_guard_takes_page_back;
import 'rejected_nested_guard_takes_tabs_or_deferred_page_back_test.dart'
    as rejected_nested_guard_takes_tabs_or_deferred_page_back;
import 'rejected_nested_navigation_keeps_route_data_test.dart'
    as rejected_nested_navigation_keeps_route_data;
import 'relative_path_colon_test.dart' as relative_path_colon;
import 'reload_guard_test.dart' as reload_guard;
import 'reload_hero_test.dart' as reload_hero;
import 'remove_last_then_push_same_test.dart' as remove_last_then_push_same;
import 'remove_route_kept_handle_test.dart' as remove_route_kept_handle;
import 'remove_where_same_route_test.dart' as remove_where_same_route;
import 'repeated_query_key_number_test.dart' as repeated_query_key_number;
import 'repeated_query_key_test.dart' as repeated_query_key;
import 'replace_all_ends_held_page_test.dart' as replace_all_ends_held_page;
import 'replace_all_from_deep_stack_test.dart' as replace_all_from_deep_stack;
import 'replace_all_from_redirect_page_test.dart'
    as replace_all_from_redirect_page;
import 'replace_all_guard_page_caller_waits_test.dart'
    as replace_all_guard_page_caller_waits;
import 'replace_all_guard_page_nested_pages_test.dart'
    as replace_all_guard_page_nested_pages;
import 'replace_all_guard_page_of_top_route_test.dart'
    as replace_all_guard_page_of_top_route;
import 'replace_all_guard_page_replaced_test.dart'
    as replace_all_guard_page_replaced;
import 'replace_all_guard_page_test.dart' as replace_all_guard_page;
import 'replace_all_keeps_screen_below_top_test.dart'
    as replace_all_keeps_screen_below_top;
import 'replace_all_kept_screen_shows_new_children_test.dart'
    as replace_all_kept_screen_shows_new_children;
import 'replace_all_kept_shell_keeps_its_route_data_test.dart'
    as replace_all_kept_shell_keeps_its_route_data;
import 'replace_all_on_reevaluation_test.dart' as replace_all_on_reevaluation;
import 'replace_all_parent_then_child_test.dart'
    as replace_all_parent_then_child;
import 'replace_all_rejected_test.dart' as replace_all_rejected;
import 'replace_all_shell_on_top_waits_for_guards_test.dart'
    as replace_all_shell_on_top_waits_for_guards;
import 'replace_all_slow_guard_test.dart' as replace_all_slow_guard;
import 'replace_all_then_push_test.dart' as replace_all_then_push;
import 'replace_changed_path_param_test.dart' as replace_changed_path_param;
import 'replace_path_rejected_test.dart' as replace_path_rejected;
import 'replace_push_pop_test.dart' as replace_push_pop;
import 'replace_rejected_test.dart' as replace_rejected;
import 'replace_same_route_children_test.dart' as replace_same_route_children;
import 'replace_then_pop_test.dart' as replace_then_pop;
import 'replace_while_animating_out_test.dart' as replace_while_animating_out;
import 'replace_with_new_children_test.dart' as replace_with_new_children;
import 'replace_with_unlisted_tab_test.dart' as replace_with_unlisted_tab;
import 'replaced_change_skips_later_guards_test.dart'
    as replaced_change_skips_later_guards;
import 'replaced_push_future_test.dart' as replaced_push_future;
import 'required_args_test.dart' as required_args;
import 'restore_args_test.dart' as restore_args;
import 'restore_declarative_link_children_test.dart'
    as restore_declarative_link_children;
import 'restore_history_test.dart' as restore_history;
import 'restore_inherited_path_param_test.dart' as restore_inherited_path_param;
import 'restore_stack_test.dart' as restore_stack;
import 'restore_tabs_test.dart' as restore_tabs;
import 'restore_with_link_test.dart' as restore_with_link;
import 'rewritten_link_back_test.dart' as rewritten_link_back;
import 'root_bottom_sheet_aware_test.dart' as root_bottom_sheet_aware;
import 'root_router_dispose_test.dart' as root_router_dispose;
import 'route_aware_deep_link_test.dart' as route_aware_deep_link;
import 'route_aware_in_dialog_test.dart' as route_aware_in_dialog;
import 'route_aware_mixin_test.dart' as route_aware_mixin;
import 'route_aware_pop_order_test.dart' as route_aware_pop_order;
import 'route_leave_test.dart' as route_leave;
import 'route_not_found_tree_test.dart' as route_not_found_tree;
import 'routes_change_while_guard_decides_test.dart'
    as routes_change_while_guard_decides;
import 'same_route_tabs_keep_active_test.dart' as same_route_tabs_keep_active;
import 'same_route_tabs_path_test.dart' as same_route_tabs_path;
import 'same_route_tabs_reevaluation_test.dart' as same_route_tabs_reevaluation;
import 'screen_reached_again_keeps_caller_test.dart'
    as screen_reached_again_keeps_caller;
import 'screen_reached_again_keeps_leave_listener_test.dart'
    as screen_reached_again_keeps_leave_listener;
import 'set_aside_page_asked_when_back_test.dart'
    as set_aside_page_asked_when_back;
import 'set_query_param_read_test.dart' as set_query_param_read;
import 'set_query_param_test.dart' as set_query_param;
import 'sign_in_closes_awaited_redirect_test.dart'
    as sign_in_closes_awaited_redirect;
import 'sign_out_during_back_closes_page_test.dart'
    as sign_out_during_back_closes_page;
import 'sign_out_while_push_guard_awaits_test.dart'
    as sign_out_while_push_guard_awaits;
import 'simultaneous_taps_test.dart' as simultaneous_taps;
import 'slow_link_builder_order_test.dart' as slow_link_builder_order;
import 'stack_emptied_under_dialog_test.dart' as stack_emptied_under_dialog;
import 'state_after_reload_test.dart' as state_after_reload;
import 'swipe_init_tab_test.dart' as swipe_init_tab;
import 'swipe_unopened_tab_rtl_vertical_test.dart'
    as swipe_unopened_tab_rtl_vertical;
import 'switch_routers_test.dart' as switch_routers;
import 'tab_bar_dispose_test.dart' as tab_bar_dispose;
import 'tab_bar_drag_during_tab_change_test.dart'
    as tab_bar_drag_during_tab_change;
import 'tab_bar_indicator_test.dart' as tab_bar_indicator;
import 'tab_bar_list_change_during_move_test.dart'
    as tab_bar_list_change_during_move;
import 'tab_bar_zero_duration_guard_test.dart' as tab_bar_zero_duration_guard;
import 'tab_cached_context_test.dart' as tab_cached_context;
import 'tab_guard_override_children_test.dart' as tab_guard_override_children;
import 'tab_guards_test.dart' as tab_guards;
import 'tab_history_back_rebuild_test.dart' as tab_history_back_rebuild;
import 'tab_history_back_test.dart' as tab_history_back;
import 'tab_inner_router_test.dart' as tab_inner_router;
import 'tab_navigate_path_query_test.dart' as tab_navigate_path_query;
import 'tab_rebuild_test.dart' as tab_rebuild;
import 'tab_removed_test.dart' as tab_removed;
import 'tab_required_args_refresh_test.dart' as tab_required_args_refresh;
import 'tab_routes_change_test.dart' as tab_routes_change;
import 'tab_routes_index_test.dart' as tab_routes_index;
import 'tab_semantics_test.dart' as tab_semantics;
import 'tab_shared_parent_url_test.dart' as tab_shared_parent_url;
import 'tab_shared_route_navigate_test.dart' as tab_shared_route_navigate;
import 'tab_switch_then_dispose_test.dart' as tab_switch_then_dispose;
import 'tab_view_page_controller_test.dart' as tab_view_page_controller;
import 'tabs_deep_link_test.dart' as tabs_deep_link;
import 'tabs_duration_update_test.dart' as tabs_duration_update;
import 'tabs_page_view_page_controller_test.dart'
    as tabs_page_view_page_controller;
import 'tabs_pop_scope_test.dart' as tabs_pop_scope;
import 'tabs_scaffold_build_count_test.dart' as tabs_scaffold_build_count;
import 'tabs_url_without_initial_test.dart' as tabs_url_without_initial;
import 'taken_over_screen_keeps_caller_test.dart'
    as taken_over_screen_keeps_caller;
import 'theme_change_test.dart' as theme_change;
import 'theme_page_transitions_test.dart' as theme_page_transitions;
import 'two_links_into_nested_router_test.dart' as two_links_into_nested_router;
import 'two_navigations_to_one_page_test.dart' as two_navigations_to_one_page;
import 'two_pushes_one_turn_test.dart' as two_pushes_one_turn;
import 'two_refused_links_into_new_page_test.dart'
    as two_refused_links_into_new_page;
import 'typed_screen_reached_again_test.dart' as typed_screen_reached_again;
import 'typed_url_test.dart' as typed_url;
import 'unanswered_push_guard_sign_out_test.dart'
    as unanswered_push_guard_sign_out;
import 'unbuilt_nested_router_while_guard_decides_test.dart'
    as unbuilt_nested_router_while_guard_decides;
import 'universal_link_test.dart' as universal_link;
import 'unmatched_deep_link_test.dart' as unmatched_deep_link;
import 'unopened_tab_children_after_reevaluation_test.dart'
    as unopened_tab_children_after_reevaluation;
import 'url_after_tab_switch_test.dart' as url_after_tab_switch;
import 'url_encoded_once_test.dart' as url_encoded_once;
import 'url_on_pop_test.dart' as url_on_pop;
import 'url_on_push_in_shell_test.dart' as url_on_push_in_shell;
import 'url_path_separator_test.dart' as url_path_separator;
import 'wait_for_transitions_after_page_update_test.dart'
    as wait_for_transitions_after_page_update;
import 'wait_for_transitions_test.dart' as wait_for_transitions;
import 'wildcard_route_pushed_url_test.dart' as wildcard_route_pushed_url;
import 'window_resize_test.dart' as window_resize;
import 'wrapper_push_from_child_test.dart' as wrapper_push_from_child;

// Runs every integration test file in one app launch. Run this file, not the
// folder: desktop runners fail to relaunch the app for a second file, and
// `flutter drive` on web takes a single target. Add each new test file here.
// Runs the other files; it is not a test file itself.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  active_guard_observer.main();
  active_tab_removed.main();
  ancestor_path_params.main();
  android_back_in_app.main();
  app_call_into_unopened_tab_waits.main();
  app_smoke.main();
  app_tab_change_waits_for_nested_guards.main();
  async_simple_guard.main();
  back_after_closing_nested_router_page.main();
  back_after_closing_unbuilt_page.main();
  back_after_link_page_removed.main();
  back_after_link_to_other_tab.main();
  back_after_navigations_in_one_turn.main();
  back_after_opening_nested_pages_together.main();
  back_after_opening_pages_together_in_tabs.main();
  back_after_pages_opened_together.main();
  back_after_push_all_in_hidden_tab.main();
  back_after_push_all.main();
  back_after_refused_navigation.main();
  back_after_reload.main();
  back_after_remove_until_in_hidden_tab.main();
  back_after_removing_link_page.main();
  back_after_sign_in.main();
  back_after_tab_change_with_waiting_guard.main();
  back_in_declarative_router.main();
  back_in_tabs.main();
  back_into_other_tab_asks_only_tab_guards.main();
  back_into_tab_with_sign_in_redirect.main();
  back_into_waiting_tab_guard.main();
  back_leaves_waiting_link.main();
  back_rejected_by_guard.main();
  back_same_route_params.main();
  back_same_url.main();
  back_skips_removed_page.main();
  back_through_every_open_page.main();
  back_to_open_page_asks_no_guard.main();
  back_to_shell_home.main();
  back_twice_in_one_turn.main();
  back_twice.main();
  back_while_nested_guard_waits.main();
  batch_rejected_keeps_caller.main();
  batch_rejected_keeps_stack.main();
  batch_slow_guard.main();
  bool_query_param.main();
  browser_back_to_open_page_asks_no_guard.main();
  callback_guard_stale_yes.main();
  camel_case_path.main();
  change_during_guard_check.main();
  change_during_navigation_guard.main();
  change_in_later_round.main();
  child_route_fragment.main();
  closed_tabs_end_held_tab.main();
  covered_window.main();
  cupertino_page_pop_scope_with_drawer.main();
  cupertino_title_after_page_update.main();
  current_hierarchy.main();
  current_url.main();
  custom_route_barrier_dismissible.main();
  custom_route_current_result.main();
  custom_route_query_params.main();
  custom_route_swipe_back.main();
  custom_route_transition.main();
  custom_route_underneath.main();
  declarative_hero_controller.main();
  declarative_initial_routes.main();
  declarative_leading_button_after_pop.main();
  declarative_on_navigate_once.main();
  declarative_popped_page_still_listed.main();
  declarative_push_message.main();
  declarative_router_key.main();
  declarative_router_of.main();
  declarative_routes_update.main();
  declarative_update_keeps_nested_router.main();
  deep_link_parent_build.main();
  deferred_and_eager_page.main();
  deferred_page_failed_load_retry.main();
  deferred_page_popped.main();
  deferred_widget_own_placeholder.main();
  dialog_args_route_information.main();
  dialog_then_page_animates.main();
  dialog_then_page_pop.main();
  disposed_nested_router.main();
  dollar_names.main();
  dropped_tab_without_initial_child.main();
  duplicate_path.main();
  eager_tabs.main();
  empty_list_query_param.main();
  empty_nested_router.main();
  empty_query_value.main();
  encoded_deep_link.main();
  encoded_link_back.main();
  encoded_path_params.main();
  encoded_url.main();
  enum_query_param.main();
  forward_after_tabs_page_closes.main();
  forward_jump_opens_passed_pages.main();
  forward_with_sign_in_redirect.main();
  fragment_question_mark_url.main();
  full_url_nested_path.main();
  generic_page.main();
  guard_answers_at_once.main();
  guard_answers_each_call.main();
  guard_lets_go_keeps_router.main();
  guard_throws_tab.main();
  guard_throws.main();
  guarded_tab_link_after_tabs_left.main();
  held_back_page_after_rebuild.main();
  held_back_page_leaves_screen.main();
  held_page_guard_error.main();
  hero_controller_builder.main();
  hero_nested_router.main();
  home_index_back.main();
  home_index_update.main();
  host_back_button.main();
  hot_reload_routes.main();
  indexed_stack_curved_animation.main();
  inherited_id_child.main();
  inherited_order_id.main();
  insert_under_no_history_top.main();
  invalid_utf8_escape_link.main();
  keep_history.main();
  late_router_deep_link.main();
  leading_button_drawer.main();
  leading_button_nested_page_removed.main();
  leading_button_nested_pageless_route.main();
  leading_button_pop.main();
  let_go_navigate_one_copy.main();
  let_go_only_page_above.main();
  let_go_only_page.main();
  let_go_page_above.main();
  let_go_push_other_args.main();
  let_go_redirect_cancel.main();
  let_go_stale_yes.main();
  link_after_route_without_page.main();
  link_during_initial_guard.main();
  link_into_eager_tab_with_waiting_guard.main();
  link_into_open_tabs_page.main();
  link_to_guarded_page_in_waiting_tab.main();
  link_to_removed_tab.main();
  link_url_while_guard_decides.main();
  list_query_param.main();
  listener_asks_for_waiting_tab.main();
  login_state.main();
  logout_redirect_back.main();
  maybe_pop_over_nested_router_in_one_turn.main();
  moved_router_keeps_pages.main();
  navigate_absolute_path.main();
  navigate_after_dialog.main();
  navigate_awaits.main();
  navigate_inherited_path_params.main();
  navigate_into_open_page_keeps_dialog.main();
  navigate_nested_update.main();
  navigate_open_shell_no_children.main();
  navigate_over_pageless_route.main();
  navigate_reaches_nested_router_in_call.main();
  navigate_rejected_keeps_stack.main();
  navigate_root_from_nested.main();
  navigate_to_active_tab_while_guard_decides.main();
  navigate_to_non_tab.main();
  navigate_to_unlisted_page_in_unopened_tab.main();
  navigate_to_unshown_tab_keeps_children.main();
  navigation_closes_held_page.main();
  navigation_into_tab_waits_for_nested_guards.main();
  navigations_in_one_turn.main();
  nested_absolute_redirect.main();
  nested_back.main();
  nested_browser_back.main();
  nested_did_pop.main();
  nested_generated_path_url.main();
  nested_pop_scope_first_page.main();
  nested_pop_scope_step.main();
  nested_redirect_before_wildcard.main();
  nested_redirect_shorter_path.main();
  nested_result.main();
  nested_route_aware.main();
  nested_route_fragment.main();
  nested_router_semantics.main();
  nested_router_text_field_focus.main();
  nested_shell_back.main();
  nested_tab_bar_reevaluation.main();
  non_ascii_url.main();
  opened_at_rewritten_url.main();
  opened_at_tab_with_waiting_guard.main();
  optional_args_on_back.main();
  overlapping_reevaluation.main();
  override_args_on_reevaluate.main();
  override_children_on_reevaluate.main();
  page_semantics_identifier.main();
  page_taken_off_while_reevaluating.main();
  page_view_fast_guard_swipe.main();
  page_view_quick_tab_changes.main();
  page_view_second_swipe_guard.main();
  page_view_swipe_back.main();
  page_view_tabs_under_cover.main();
  page_view_zero_duration.main();
  pageless_push_rebuild.main();
  pages_above_rejected_page_removed.main();
  pages_over_open_page_wait_for_nested_guards.main();
  param_converter.main();
  parent_pages_build.main();
  path_key_link_then_navigate.main();
  path_state_after_replace.main();
  path_state_browser_back.main();
  platform_link_over_launch_page.main();
  pop_after_removal_at_frame_end.main();
  pop_after_replace_in_one_turn.main();
  pop_and_back.main();
  pop_and_push_all.main();
  pop_and_push_browser_back.main();
  pop_and_push_from_animating_modal.main();
  pop_push_pop.main();
  pop_right_after_push.main();
  pop_scope_once.main();
  pop_scope.main();
  pop_until_back_history.main();
  pop_until_before_build.main();
  pop_until_browser_back.main();
  pop_until_hides_middle.main();
  pop_until_missing_route.main();
  pop_until_path_then_push_in_one_turn.main();
  pop_until_then_push_in_one_turn.main();
  pop_while_held_back.main();
  pop_while_reevaluating.main();
  popped_args_released.main();
  predictive_back_nested_under_root.main();
  prefix_matches_nested.main();
  prefix_matches_tabs.main();
  prefix_stripper.main();
  push_all_nested_routes.main();
  push_all_waits_for_guard.main();
  push_and_pop_until_async.main();
  push_and_pop_until_flash.main();
  push_and_pop_until_into_tabs_page.main();
  push_and_pop_until.main();
  push_and_pop_until_with_name_in_one_turn.main();
  push_and_reevaluate.main();
  push_futures.main();
  push_into_nested_guard_takes_page_back.main();
  push_same_route_twice.main();
  push_then_replace.main();
  push_to_tab_with_waiting_guard.main();
  push_unknown_relative_path.main();
  query_param_rebuild.main();
  query_params_on_pop.main();
  query_toggle_back.main();
  rapid_pops.main();
  rebuild_stack_back_and_forward.main();
  rebuild_stack_rejected_link.main();
  redirect_cycle.main();
  redirect_fragment.main();
  redirect_history.main();
  redirect_in_closed_nested_router.main();
  redirect_lifecycle.main();
  redirect_loop.main();
  redirect_param_name_prefix.main();
  redirect_partly_matched_target.main();
  redirect_path_param.main();
  redirect_replace_rejected.main();
  redirect_route_cycle.main();
  redirect_target_colon.main();
  reevaluate_asks_active_tab_guards.main();
  reevaluate_covered_nested_router.main();
  reevaluate_deep_link.main();
  reevaluate_guarded_tab_child.main();
  reevaluate_slow_guard_rebuild.main();
  reevaluation_nested_tabs.main();
  reevaluation_redirect.main();
  reject_go_back_link_keeps_stack.main();
  rejected_child_of_unbuilt_nested_router.main();
  rejected_initial_link_url.main();
  rejected_launch_guarded_first_page.main();
  rejected_launch_shows_first_page.main();
  rejected_link_into_other_tab.main();
  rejected_link_keeps_dialog.main();
  rejected_link_keeps_earlier_link.main();
  rejected_link_url_running.main();
  rejected_nested_guard_keeps_pages_closing.main();
  rejected_nested_guard_takes_page_back.main();
  rejected_nested_guard_takes_tabs_or_deferred_page_back.main();
  rejected_nested_navigation_keeps_route_data.main();
  relative_path_colon.main();
  reload_guard.main();
  reload_hero.main();
  remove_last_then_push_same.main();
  remove_route_kept_handle.main();
  remove_where_same_route.main();
  repeated_query_key_number.main();
  repeated_query_key.main();
  replace_all_ends_held_page.main();
  replace_all_from_deep_stack.main();
  replace_all_from_redirect_page.main();
  replace_all_guard_page_caller_waits.main();
  replace_all_guard_page_nested_pages.main();
  replace_all_guard_page_of_top_route.main();
  replace_all_guard_page_replaced.main();
  replace_all_guard_page.main();
  replace_all_keeps_screen_below_top.main();
  replace_all_kept_screen_shows_new_children.main();
  replace_all_kept_shell_keeps_its_route_data.main();
  replace_all_on_reevaluation.main();
  replace_all_parent_then_child.main();
  replace_all_rejected.main();
  replace_all_shell_on_top_waits_for_guards.main();
  replace_all_slow_guard.main();
  replace_all_then_push.main();
  replace_changed_path_param.main();
  replace_path_rejected.main();
  replace_push_pop.main();
  replace_rejected.main();
  replace_same_route_children.main();
  replace_then_pop.main();
  replace_while_animating_out.main();
  replace_with_new_children.main();
  replace_with_unlisted_tab.main();
  replaced_change_skips_later_guards.main();
  replaced_push_future.main();
  required_args.main();
  restore_args.main();
  restore_declarative_link_children.main();
  restore_history.main();
  restore_inherited_path_param.main();
  restore_stack.main();
  restore_tabs.main();
  restore_with_link.main();
  rewritten_link_back.main();
  root_bottom_sheet_aware.main();
  root_router_dispose.main();
  route_aware_deep_link.main();
  route_aware_in_dialog.main();
  route_aware_mixin.main();
  route_aware_pop_order.main();
  route_leave.main();
  route_not_found_tree.main();
  routes_change_while_guard_decides.main();
  same_route_tabs_keep_active.main();
  same_route_tabs_path.main();
  same_route_tabs_reevaluation.main();
  screen_reached_again_keeps_caller.main();
  screen_reached_again_keeps_leave_listener.main();
  set_aside_page_asked_when_back.main();
  set_query_param_read.main();
  set_query_param.main();
  sign_in_closes_awaited_redirect.main();
  sign_out_during_back_closes_page.main();
  sign_out_while_push_guard_awaits.main();
  simultaneous_taps.main();
  slow_link_builder_order.main();
  stack_emptied_under_dialog.main();
  state_after_reload.main();
  swipe_init_tab.main();
  swipe_unopened_tab_rtl_vertical.main();
  switch_routers.main();
  tab_bar_dispose.main();
  tab_bar_drag_during_tab_change.main();
  tab_bar_indicator.main();
  tab_bar_list_change_during_move.main();
  tab_bar_zero_duration_guard.main();
  tab_cached_context.main();
  tab_guard_override_children.main();
  tab_guards.main();
  tab_history_back_rebuild.main();
  tab_history_back.main();
  tab_inner_router.main();
  tab_navigate_path_query.main();
  tab_rebuild.main();
  tab_removed.main();
  tab_required_args_refresh.main();
  tab_routes_change.main();
  tab_routes_index.main();
  tab_semantics.main();
  tab_shared_parent_url.main();
  tab_shared_route_navigate.main();
  tab_switch_then_dispose.main();
  tab_view_page_controller.main();
  tabs_deep_link.main();
  tabs_duration_update.main();
  tabs_page_view_page_controller.main();
  tabs_pop_scope.main();
  tabs_scaffold_build_count.main();
  tabs_url_without_initial.main();
  taken_over_screen_keeps_caller.main();
  theme_change.main();
  theme_page_transitions.main();
  two_links_into_nested_router.main();
  two_navigations_to_one_page.main();
  two_pushes_one_turn.main();
  two_refused_links_into_new_page.main();
  typed_screen_reached_again.main();
  typed_url.main();
  unanswered_push_guard_sign_out.main();
  unbuilt_nested_router_while_guard_decides.main();
  universal_link.main();
  unmatched_deep_link.main();
  unopened_tab_children_after_reevaluation.main();
  url_after_tab_switch.main();
  url_encoded_once.main();
  url_on_pop.main();
  url_on_push_in_shell.main();
  url_path_separator.main();
  wait_for_transitions_after_page_update.main();
  wait_for_transitions.main();
  wildcard_route_pushed_url.main();
  window_resize.main();
  wrapper_push_from_child.main();
}

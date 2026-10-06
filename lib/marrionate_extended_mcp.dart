library;

// Flutter E2E Toolkit
export 'src/flutter_e2e_toolkit/flutter_e2e_toolkit.dart';
export 'src/flutter_e2e_toolkit/flutter_e2e_toolkit_core.dart';

// Flutter E2E MCP Server
export 'src/flutter_e2e_mcp/flutter_e2e_mcp.dart';

// E2E Key Generator
export 'src/e2e_key_generator/e2e_key_generator.dart';

// Marionette MCP
export 'src/marionette_mcp/src/formatting.dart';
export 'src/marionette_mcp/src/mcp_server_runner.dart';
export 'src/marionette_mcp/src/session/session.dart';
export 'src/marionette_mcp/src/session/session_manager.dart';
export 'src/marionette_mcp/src/session/step_logger.dart';
export 'src/marionette_mcp/src/vm_service/dynamic_extension_tools.dart';
export 'src/marionette_mcp/src/vm_service/vm_service_connector.dart';
export 'src/marionette_mcp/src/vm_service/vm_service_context.dart';
export 'src/marionette_mcp/src/vm_service/tools/ancestor_keys_description.dart';
export 'src/marionette_mcp/src/vm_service/tools/arg_coercion.dart';
export 'src/marionette_mcp/src/vm_service/tools/device_tools.dart';
export 'src/marionette_mcp/src/vm_service/tools/extension_tools.dart';
export 'src/marionette_mcp/src/vm_service/tools/gesture_tools.dart';
export 'src/marionette_mcp/src/vm_service/tools/inspection_tools.dart';
export 'src/marionette_mcp/src/vm_service/tools/keyboard_tools.dart';
export 'src/marionette_mcp/src/vm_service/tools/system_tools.dart';
export 'src/marionette_mcp/src/vm_service/tools/text_tools.dart';
export 'src/marionette_mcp/src/vm_service/tools/tool_runner.dart';

// Marionette Flutter
export 'src/marionette_flutter/e2e_marionette_flutter.dart';

// Marionette CLI
export 'src/marionette_cli/src/instance_registry.dart';
export 'src/marionette_cli/src/cli/marionette_command_runner.dart';
export 'src/marionette_cli/src/cli/matcher_builder.dart' hide hasSelector;

// Marionette Logger
export 'src/marionette_logger/e2e_marionette_logger.dart';

// Marionette Logging
export 'src/marionette_logging/e2e_marionette_logging.dart';

// Flutter Skill
export 'src/flutter_skill/e2e_flutter_skill.dart';
export 'src/flutter_skill/flutter_skill_semantic_refs.dart';
export 'src/flutter_skill/src/flutter_skill_client.dart';
export 'src/flutter_skill/src/server_registry.dart';
export 'src/flutter_skill/src/skill_client.dart';
export 'src/flutter_skill/src/skill_server.dart';
export 'src/flutter_skill/src/bridge/bridge.dart';
export 'src/flutter_skill/src/bridge/bridge_protocol.dart';
export 'src/flutter_skill/src/bridge/cdp_driver.dart';
export 'src/flutter_skill/src/bridge/device_presets.dart';
export 'src/flutter_skill/src/bridge/web_bridge_listener.dart';
export 'src/flutter_skill/src/bridge/web_bridge_proxy.dart';
export 'src/flutter_skill/src/discovery/bridge_discovery.dart';
export 'src/flutter_skill/src/discovery/discovery.dart';
export 'src/flutter_skill/src/discovery/dtd_service_discovery.dart';
export 'src/flutter_skill/src/discovery/process_based_discovery.dart';
export 'src/flutter_skill/src/discovery/quick_port_check.dart';
export 'src/flutter_skill/src/discovery/unified_discovery.dart';
export 'src/flutter_skill/src/drivers/app_driver.dart';
export 'src/flutter_skill/src/drivers/bridge_driver.dart';
export 'src/flutter_skill/src/drivers/drivers.dart';
export 'src/flutter_skill/src/drivers/flutter_driver.dart';
export 'src/flutter_skill/src/drivers/native_driver.dart';
export 'src/flutter_skill/src/drivers/web_bridge_driver.dart';
export 'src/flutter_skill/src/engine/skill_engine.dart';
export 'src/flutter_skill/src/engine/tool_registry.dart' hide ToolRegistry;
export 'src/flutter_skill/src/protocol/mcp_adapter.dart';

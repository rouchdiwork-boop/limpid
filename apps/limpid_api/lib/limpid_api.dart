/// API Dart de Limpid : monolithe modulaire `shelf` déployé sur Railway.
///
/// Le package expose le contrat REST + WebSocket décrit dans
/// `docs/ARCHITECTURE.md` §6. Il ne dépend jamais de Flutter : le modèle de
/// domaine et le moteur CRDT viennent de `limpid_core`, la passerelle IA de
/// `limpid_ai` et le moteur d'export de `limpid_export`.
library;

export 'src/auth/auth_context.dart';
export 'src/auth/auth_middleware.dart';
export 'src/auth/jwks.dart';
export 'src/auth/jwt_verifier.dart';
export 'src/auth/rsa.dart';
export 'src/config/app_config.dart';
export 'src/db/account_purge_store.dart';
export 'src/db/audit_entry.dart';
export 'src/db/audit_log.dart';
export 'src/db/comment_store.dart';
export 'src/db/database.dart';
export 'src/db/in_memory_account_purge_store.dart';
export 'src/db/in_memory_project_store.dart';
export 'src/db/in_memory_sync_store.dart';
export 'src/db/migration_runner.dart';
export 'src/db/postgres_audit_log.dart';
export 'src/db/postgres_project_store.dart';
export 'src/db/postgres_sync_store.dart';
export 'src/db/project_record.dart';
export 'src/db/project_store.dart';
export 'src/db/sql_account_purge_store.dart';
export 'src/db/sqlite_audit_log.dart';
export 'src/db/sqlite_database.dart';
export 'src/db/sqlite_migration_runner.dart';
export 'src/db/sqlite_project_store.dart';
export 'src/db/sqlite_sync_store.dart';
export 'src/db/sqlite_values.dart';
export 'src/db/sync_op_record.dart';
export 'src/db/sync_store.dart';
export 'src/dependencies.dart';
export 'src/errors/app_exception.dart';
export 'src/http/api_response.dart';
export 'src/http/json_body.dart';
export 'src/http/pagination.dart';
export 'src/logging/logger.dart';
export 'src/middleware/cors.dart';
export 'src/middleware/error_handler.dart';
export 'src/middleware/rate_limiter.dart';
export 'src/middleware/request_id.dart';
export 'src/middleware/request_logging.dart';
export 'src/middleware/timeout.dart';
export 'src/production_dependencies.dart';
export 'src/redis/key_value_store.dart';
export 'src/redis/redis_client.dart';
export 'src/routes/api_router.dart';
export 'src/routes/comment_routes.dart';
export 'src/routes/publication_author_routes.dart';
export 'src/routes/publication_routes.dart';
export 'src/server.dart';
export 'src/services/access_control.dart';
export 'src/services/account_deletion.dart';
export 'src/services/account_purge.dart';
export 'src/services/account_purge_scheduler.dart';
export 'src/services/ai_gateway.dart';
export 'src/services/book_builder.dart';
export 'src/services/document_ownership.dart';
export 'src/services/idempotency_service.dart';
export 'src/services/limpid_ai_gateway.dart';
export 'src/services/payment_gateway.dart';
export 'src/services/personal_data_export.dart';
export 'src/services/sync_hub.dart';
export 'src/storage/object_storage.dart';
export 'src/storage/sig_v4.dart';
export 'src/sync/sync_protocol.dart';
export 'src/sync/tree_builder.dart';

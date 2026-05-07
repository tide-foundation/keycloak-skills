# Extension patterns

How to extend Keycloak's data layer: adding new tables, columns to existing tables, intercepting writes, custom adapters, custom REST endpoints.

Version pinning: see `../SKILL.md`.

## Adding new entities (your own tables)

Implement `JpaEntityProvider`:

```java
public class MyEntityProvider implements JpaEntityProvider {
    @Override public List<Class<?>> getEntities() {
        return List.of(MyEntity.class, MyOtherEntity.class);
    }
    @Override public String getChangelogLocation() {
        return "META-INF/my-changelog-master.xml";
    }
    @Override public String getFactoryId() {
        return "my-extension";
    }
}
```

Register via `META-INF/services/org.keycloak.connections.jpa.entityprovider.JpaEntityProviderFactory`.

Your Liquibase changelog runs on startup, with its own tracking entries in `databasechangelog` keyed by your factory id. Idempotent and isolated from core changelogs.

## Adding columns to existing core tables

You CAN do this from an extension via your changelog (`<addColumn>` works against existing tables). But:

- The core entity classes (e.g., `UserEntity`) don't know about your column at compile time
- JPQL queries against core entities can't reference it (`e.myColumn` fails to parse)
- You must use **native SQL** for reads/writes, OR fork the entity classes (modify Keycloak source itself, not a true extension)

```java
em.createNativeQuery(
    "UPDATE USER_ENTITY SET MY_EXTENSION_COL = ? WHERE ID = ?")
  .setParameter(1, value)
  .setParameter(2, userId)
  .executeUpdate();
```

## Intercepting writes — Provider SPI

Override the relevant `*ProviderFactory`:

| SPI | Controls |
|---|---|
| `UserProviderFactory` | User CRUD + per-user operations |
| `RealmProviderFactory` | Realm, role, group, client writes (factored together at JPA level) |
| `RoleProviderFactory`, `GroupProviderFactory`, `ClientProviderFactory` | Some operations route through these |
| `ClientScopeProviderFactory` | Client scope operations |
| `EventListenerProviderFactory` | Audit events (post-action) |
| `UserStorageProviderFactory` | External user federation |

Your factory's `order()` must be higher than the JPA default (1). Or pin via `keycloak.conf`:
```
spi-user--provider=my-user-provider
spi-realm--provider=my-realm-provider
```

Your provider extends `JpaUserProvider` (etc.) and overrides specific methods.

## Wrapping returned models

For intercepting `setAttribute`, `grantRole`, `joinGroup`, etc., return wrapped adapters from your provider:

```java
public class MyUserAdapter extends UserAdapter {
    public MyUserAdapter(KeycloakSession session, RealmModel realm, EntityManager em, UserEntity user) {
        super(session, realm, em, user);
    }
    @Override
    public void grantRole(RoleModel role) {
        // your interception logic
        super.grantRole(role);  // or skip to defer
    }
}
```

**Important**: extend `UserAdapter`, don't implement `UserModel` from scratch. Keycloak code does `instanceof UserAdapter` checks and reaches for `getEntity()` — a plain UserModel proxy fails those checks.

## `KeycloakModelUtils.runJobInTransaction`

For operations that need their own transaction (e.g., persist something that must survive a rollback elsewhere):

```java
KeycloakModelUtils.runJobInTransaction(sessionFactory, newSession -> {
    EntityManager newEm = newSession.getProvider(JpaConnectionProvider.class).getEntityManager();
    RealmModel realm = newSession.realms().getRealm(realmId);
    // ... persist things — runs in fresh session + new JTA transaction
});
```

The new transaction commits independently of the calling one.

Common use cases:
- Recording an audit/IGA change request that must survive a rollback caused by throwing an exception
- Asynchronous processing
- Running migrations on demand from REST endpoints

## Avoid raw `EntityManager.persist()` for top-level entities

Always prefer the model API:
```java
// Don't:
em.persist(new UserEntity(...));

// Do:
session.users().addUser(realm, username);
```

The model API handles:
- ID generation
- Default attributes
- Default-roles assignment (via `default-roles-<realm>` composite)
- Event firing (UserRegisteredEvent, etc.)
- Provider chain dispatch (federated user storage, etc.)

Direct `em.persist` skips all of that.

## Custom REST endpoints

Use `RealmResourceProvider` (per-realm endpoints) or `AdminRealmResourceProvider` (admin endpoints under `/admin/realms/{realm}/...`):

```java
public class MyAdminResourceProvider implements AdminRealmResourceProvider {
    @Override
    public Object getResource(KeycloakSession session, RealmModel realm, 
                              AdminPermissionEvaluator auth, AdminEventBuilder adminEvent) {
        return new MyAdminResource(session, realm, auth);
    }
    @Override public void close() {}
}

@Path("my-extension")
@Vetoed   // tell Quarkus to skip CDI scanning — Keycloak constructs via factory
public class MyAdminResource {
    public MyAdminResource(KeycloakSession session, RealmModel realm, AdminPermissionEvaluator auth) { ... }
    
    @GET @Path("things")
    public Response listThings() { ... }
}
```

Register the factory in `META-INF/services/org.keycloak.services.resources.admin.ext.AdminRealmResourceProviderFactory`.

The `@Vetoed` annotation is critical — without it Quarkus tries to make the resource a CDI bean and fails because `RealmModel` and `AdminPermissionEvaluator` aren't CDI-managed.

## Custom event listeners

For audit logging or side-effects:

```java
public class MyEventListener implements EventListenerProvider {
    @Override
    public void onEvent(Event event) {
        // user-facing events: LOGIN, LOGOUT, etc.
    }
    @Override
    public void onEvent(AdminEvent event, boolean includeRepresentation) {
        // admin operations: CREATE, UPDATE, DELETE on resources
    }
    @Override public void close() {}
}
```

Register via `EventListenerProviderFactory`. Listeners run per-realm if enabled in `realm_events_listeners`.

## Custom credential types

Implement `CredentialProvider<MyCredentialModel>`:
- Hash/encrypt the credential
- Validate user-provided credentials
- Convert between `CredentialModel` (DB form) and your domain type

Register via `CredentialProviderFactory`.

## Custom user storage providers

For federating users from external sources (LDAP, custom DB, SaaS):

```java
public class MyUserStorageProvider implements UserStorageProvider, UserLookupProvider {
    @Override
    public UserModel getUserById(RealmModel realm, String id) {
        // dispatch to external system, return a UserModel adapter
    }
    @Override public UserModel getUserByUsername(RealmModel realm, String username) { ... }
    @Override public UserModel getUserByEmail(RealmModel realm, String email) { ... }
    @Override public void close() {}
}
```

Register via `UserStorageProviderFactory` with a unique `getId()`.

The user is configured at runtime as a `component` row of type `org.keycloak.storage.UserStorageProvider`. Per-user data Keycloak adds (roles, attributes, consents) goes in `fed_user_*` tables — your provider handles the rest.

## Liquibase tips

- Use `<preConditions>` to make changesets idempotent — important for upgrades
- Always include `id` and `author` attributes; they form the unique key in `databasechangelog`
- For column adds: `<addColumn>` with `<column>` defining type, default, nullable
- For renames: `<renameColumn>` (works on most DBs — Postgres/MySQL/MSSQL/Oracle/H2)
- For data migrations: `<update>` or `<sql>` with explicit conditions
- Test against H2 (Keycloak's dev DB) and PostgreSQL (most common production)

```xml
<changeSet id="my-1.0.0-1" author="my-extension">
    <preConditions onFail="MARK_RAN">
        <not><tableExists tableName="MY_TABLE"/></not>
    </preConditions>
    <createTable tableName="MY_TABLE">
        <column name="ID" type="VARCHAR(36)">
            <constraints primaryKey="true" nullable="false"/>
        </column>
        <column name="REALM_ID" type="VARCHAR(36)">
            <constraints nullable="false" foreignKeyName="FK_MY_TABLE_REALM" 
                         references="REALM(ID)"/>
        </column>
        <!-- ... -->
    </createTable>
</changeSet>
```

## Master changelog file

Your factory points at a master file that includes per-version changelogs:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<databaseChangeLog
    xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
                        http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-3.8.xsd">
    
    <include file="META-INF/my-changelog-1.0.0.xml"/>
    <include file="META-INF/my-changelog-1.1.0.xml"/>
</databaseChangeLog>
```

## Don't touch upstream changelogs

Never modify `jpa-changelog-*.xml` files in Keycloak source. Liquibase will refuse to start if changeset checksums change. Always ship your own changelog.

## Stale lock recovery

If Keycloak crashes mid-migration:
```
Could not acquire change log lock
```
Clear the lock manually:
```sql
UPDATE DATABASECHANGELOGLOCK SET LOCKED = FALSE, LOCKEDBY = NULL, LOCKGRANTED = NULL WHERE ID = 1;
```

## Cascade considerations when intercepting deletes

If you intercept a delete and want to defer it (approval workflow), Keycloak will trigger child cascades automatically. Strategies:

1. **Intercept at REST layer**: catch the DELETE request, return 409, never let `model.removeX()` run
2. **Intercept at model layer + throw**: throw an exception in your provider's removeX override; the transaction rolls back including any partial cleanup
3. **Use `KeycloakModelUtils.runJobInTransaction`** to do the actual delete in a separate transaction once approved

DON'T try to:
- Persist a "tombstone" row for a deferred delete — DB cascade fires regardless
- Do the cleanup yourself before deleting the parent — confuses the model API

## See also

- `entities.md` — full table catalog
- `authorization-services.md` — UMA-specific extension via `PolicyProvider`
- `../SKILL.md` — schema patterns, common gotchas, JPQL examples

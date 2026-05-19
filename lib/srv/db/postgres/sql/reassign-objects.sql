CREATE OR REPLACE PROCEDURE pg_temp.teleport_reassign_objects(username varchar, orphaned_resource_owner varchar)
LANGUAGE plpgsql
AS $$
BEGIN
    -- For REASSIGN OWNED BY to work, the admin user must be a member of both
    -- orphaned_resource_owner and username. For username, we simply GRANT
    -- it to the admin user. For orphaned_resource_owner, we require that
    -- the admin user is already a member of it.
    BEGIN
        EXECUTE FORMAT('GRANT %I TO CURRENT_USER', username);
        EXECUTE FORMAT('REASSIGN OWNED BY %I TO %I', username, orphaned_resource_owner);
        EXECUTE FORMAT('REVOKE %I FROM CURRENT_USER', username);
    EXCEPTION
        WHEN others THEN
            RAISE WARNING 'Failed to reassign objects from user % to user %: %, SQLSTATE=%', username, orphaned_resource_owner, SQLERRM, SQLSTATE;
    END;
END;$$;

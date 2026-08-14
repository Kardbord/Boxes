# OBS Bug: `Token::ServicePolicy` cannot authorize trigger for scmsync-managed packages

**Status:** Open (observed Aug 2026) — not filed upstream yet
**Upstream repo:** openSUSE/open-build-service
**Affected file:** `src/api/app/policies/token/service_policy.rb`

## Summary

A source-service trigger token (`Token::Service`) cannot be used to re-run the
`_service` file of a package that lives in a **project-level `scmsync`** project,
such as `home:Kardbord:Boxes`. The trigger fails with an authorization type error
instead of running the service.

## Reproduction

Create a project-wide `runservice` token and use it to trigger a service run for a
package in a `scmsync`-managed project:

```bash
# create a project-wide runservice token
osc api -X POST "/person/Kardbord/token?operation=runservice"

# attempt to trigger a service run
osc token --trigger <TOKEN> home:Kardbord:Boxes kardbord-breakout
```

Expected: OBS re-runs the package's `_service` (re-fetching upstream sources) and
queues a rebuild.

Actual — two failure modes depending on the client:

- `osc token --trigger ...`:
  ```
  Trigger token
  Server returned an error: HTTP Error 400: Bad Request
  illegal parameter type to User#can_modify_package?: Project
  ```
- `curl` against `POST /trigger/runservice?...`:
  ```
  <status code="unknown">
    <summary>illegal parameter type to User#can_modify_package?: Project</summary>
  </status>
  ```

Other trigger mechanisms hit the same wall:

- `osc service remoterun home:Kardbord:Boxes kardbord-breakout` → 403 Forbidden
  `Sorry, you are not authorized to update this package.`
- `osc api -X POST "/source/home:Kardbord:Boxes/kardbord-breakout?cmd=runservice"` → 403 Forbidden (same message)

Note: `osc rebuild home:Kardbord:Boxes kardbord-breakout` **does work**, because rebuild
authorization handles the project case (see below).

## Root cause

For a package in a project-level `scmsync` project, the package is not stored as a
local database object — its sources are synchronised into OBS by `obs_scm_bridge`
from the git repository. So `Triggerable#set_package` cannot find the `Package` in
the database.

`src/api/app/controllers/concerns/triggerable.rb` handles this by falling back to a
package-name string (mirroring the remote-project-link behaviour):

```ruby
def set_package(package_find_options: {})
  ...
  return unless project_links_to_remote?
  # In this case, we will try to trigger with the user input, no matter what it is
  @package ||= Package.striping_multibuild_suffix(@package_name)
  ...
end

def set_object_to_authorize
  @token.object_to_authorize = package_from_project_link? ? @project : @package
end

def package_from_project_link?
  !(@package.is_a?(Package) && @package.project == @project)
end

def project_links_to_remote?
  @project.scmsync.present? || @project.links_to_remote?
end
```

So `object_to_authorize` is set to the **Project**. This is correct behaviour —
the authorize target for a service run on a scmsync-managed package is the project.

The problem is the **authorization policy** for service tokens.
`src/api/app/policies/token/service_policy.rb` is:

```ruby
class Token::ServicePolicy < TokenPolicy
  def trigger?
    return false unless user.active?
    PackagePolicy.new(user, record.object_to_authorize).update?
  end
end
```

It **always** delegates to `PackagePolicy`, ignoring whether the
`object_to_authorize` is a `Package` or a `Project`. When a `Project` is passed to
`PackagePolicy`, it tries to call `User#can_modify_package?` with a `Project`
argument, producing the `illegal parameter type` error.

## Why rebuild works but runservice does not

The rebuild token policy handles the `Project` case:

```ruby
class Token::RebuildPolicy < TokenPolicy
  def trigger?
    return false unless user.active?
    return PackagePolicy.new(user, record.object_to_authorize).update? if record.object_to_authorize.is_a?(Package)
    ProjectPolicy.new(user, record.object_to_authorize).update? if record.object_to_authorize.is_a?(Project)
  end
end
```

`Token::ServicePolicy` (and not `Token::RebuildPolicy` / `Token::ReleasePolicy`) is
missing this `is_a?(Project)` fallback.

## Proposed fix

2-line change mirroring the other token policies:

```ruby
class Token::ServicePolicy < TokenPolicy
  def trigger?
    return false unless user.active?
    return PackagePolicy.new(user, record.object_to_authorize).update? if record.object_to_authorize.is_a?(Package)
    ProjectPolicy.new(user, record.object_to_authorize).update? if record.object_to_authorize.is_a?(Project)
  end
end
```

## Related work

- Issue openSUSE/open-build-service#14930 — "Missing handling of scmsync packages
  for token operations". The *rebuild* case was fixed (see PR #17701 /
  `triggerable.rb` `project_links_to_remote?`); the *service* authorization bug is
  **not** covered by that fix and no open issue documents it.
- The `osc api ... cmd=runservice` and `osc service remoterun` paths fail with 403
  because they use a different authorization path that also does not permit
  updating the source of a scmsync-managed package.

## Working around it (until fixed)

| Goal | Working method |
|---|---|
| Force a rebuild with existing sources | `osc rebuild home:Kardbord:Boxes kardbord-breakout` (or `--all`) |
| Re-run `_service` (re-fetch upstream) | Push any commit to the git repo → `scmsync` re-syncs and runs `_service` |
| Automated upstream tracking | GitHub Actions workflow that detects a new upstream tag and pushes a trivial commit to trigger `scmsync` |

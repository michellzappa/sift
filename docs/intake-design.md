# Intake design: Safari to Sift to Starlings

Status: proposal, 2026-11-14. Nothing here is built yet.

## Roles

| Layer | Holds | Lifetime |
| --- | --- | --- |
| Safari (tabs, Reading List) | Links you have not decided on | Until you close them |
| Sift | The decision: project, use, next action, preview | Until the link is filed |
| Starlings | The link, filed on a project, with your notes | Permanent |

Sift is not a bookmark store. A second store would hold the same links as
Starlings and drift from it. Sift keeps only a filed log: URL, the workspace
and the document door it went to, and the date.

## What Starlings already has

Starlings saves links natively. `docs_write` with a `url` and no `document`
fetches the page (title, description, picture, article as markdown), files it
under `/work/links` (or `folder_path`), and returns the earlier save when the
same URL comes in again. `body_md` becomes the notes. `subjects` files it on a
project; a save with no subject stays private to its author. `task` creates a
task on a subject; it has no URL field, so the link goes in `notes`.

Every write acts as the member, carries the client's name as `via`, posts a
line on the subject's channel, and takes an `idempotency_key`.

Sources in the Starlings repo: `docs/MCP.md`, `docs/DOCS.md`,
`services/control-plane/src/mcp.ts` (`docs_write`, `task`).

## Filing rules

For each sorted tab, the next action decides what Sift writes:

| Next action | Starlings write |
| --- | --- |
| Read, Cite, File | Link save on the mapped project |
| Try, Contact | Link save, plus a task on the project with the URL in `notes` |
| Close | Nothing. The tab only goes to the close list |

The link save carries:

- `url`: the tab URL.
- `subjects`: `[{kind: "project", subject_id}]` from the project mapping.
- `body_md`: the use line, then the preview text Sift already has.
- `tags`: `sift`, the next action (`read`, `cite` and so on).
- `frontmatter`: `{source: "sift", action, sift_project, tab_last_viewed}`.
- `idempotency_key`: a hash of workspace and URL, so a retry never files twice.

The task title is the action and the page title, for example "Try: obra/superpowers".

After a successful write, Sift records the returned door in its filed log,
shows "Filed" on the card with a link to the document, and adds the tab to the
iPhone close list.

## Project mapping

Sift's projects are repos and hand-made projects. Starlings projects live in
workspaces. A mapping table in Settings joins them once:

| Sift project | Workspace origin | Starlings project door |
| --- | --- | --- |
| (repo or extra project) | `https://<workspace>.starlings.work` | `subject:project:<id>` |

Settings fills the right column with a picker that calls `search` with
`kinds: ["subject"]` on each connected workspace. Several Sift projects can map
to one Starlings project.

Unmapped projects (personal work with no Starlings project) file as a private
link save on a default workspace, with no subject, under
`/work/links/<sift project>`. Starlings keeps those private to their author.

## Connection

Starlings has no API keys. Sift connects like any MCP client:

1. OAuth 2.1 with dynamic client registration at `<origin>/oauth/register`,
   PKCE S256, client name "Sift".
2. Authorization in the browser at `<origin>/oauth/authorize`. The member ticks
   "Also write" on the consent page.
3. Redirect to a loopback URL (`http://127.0.0.1:<port>/callback`). Starlings
   accepts loopback redirects for native clients.
4. Access and refresh tokens go to the login keychain, one pair per workspace.
   Refresh tokens rotate; Sift stores the new one each time.
5. Calls are JSON-RPC 2.0 `tools/call` over `POST <origin>/mcp`.

The member can pause or revoke Sift's grant in Starlings at any time.

## Batches and visibility

A link filed on a project is visible to everyone who can see that project. So
Sift files in batches that the member confirms: a sheet lists the links per
project and workspace, then one click files them. Nothing files on its own.

## Open questions

1. Unmapped projects: private link saves in a default workspace (proposed), or
   a `links.md` in the project's repo?
2. Try and Contact: a task as well as the link save (proposed), or the link
   save only?
3. Auto-close: put filed tabs on the iPhone close list at once (proposed), or
   leave closing to the member?
4. Existing research documents: Starlings projects already hold research write
   ups on the same topics as many tabs. A later step could append a "Sources"
   line to a matching document (`docs_write` with `append_md`). Out of scope
   for the first version.

## Not in scope

- A Starlings change. Everything above uses tools that exist today.
- Writing from Starlings back to Sift or Safari.

# Installing the max-messenger skill — instructions for the agent

You were asked to install this skill. Do it without asking the user questions; report at the end.
Do not edit `SKILL.md` or anything in `references/`.

The canonical copy lives in `~/.agents/skills/max-messenger/` (this folder). `install.sh` has
normally put it there and linked it for Claude Code and Cline already. Your job is to make sure
**the harness you are running in** loads it.

1. Check that `~/.agents/skills/max-messenger/SKILL.md` exists and its frontmatter says
   `name: max-messenger`. If it does not, run
   `curl -fsSLO https://raw.githubusercontent.com/max-messenger/max-agents-skill/main/install.sh && bash install.sh`
   and check again; if that fails too, stop and show the user the error.
2. Work out which harness you are, then make the skill visible to it:

   | Harness | Personal skills folder | Action |
   |---------|------------------------|--------|
   | Codex, Cursor, Gemini CLI, OpenCode, GitHub Copilot | `~/.agents/skills` (read natively) | Nothing to do |
   | Claude Code | `~/.claude/skills` | Ensure `~/.claude/skills/max-messenger` is a symlink to `~/.agents/skills/max-messenger` |
   | Cline | `~/.cline/skills` | Same symlink in `~/.cline/skills` |
   | Other harness that loads `SKILL.md` folders from disk | its own personal skills folder | Symlink `max-messenger` there; if the harness does not follow symlinks, copy the folder |
   | Claude Desktop, Cowork, claude.ai | no disk folder — skills are uploaded | Tell the user to upload `~/Downloads/max-messenger-skill.zip` (built by `install.sh`) in Settings → Skills |

   If a real folder (not a symlink) named `max-messenger` already exists in the target folder,
   move it to `~/.cache/agent-skills-backup/` before linking; never delete it.
3. If you created a skills folder that did not exist before, tell the user to restart the harness.
4. Report in two or three lines: where the skill is, which link you created (if any), and whether
   a restart is needed. Suggest a check: "Напиши бота для MAX на Go, который отвечает на /start".

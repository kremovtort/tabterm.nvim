---@alias tabterm.EventType
---| "WORKSPACE_OPEN_REQUESTED"
---| "WORKSPACE_CLOSE_REQUESTED"
---| "WORKSPACE_TOGGLE_REQUESTED"
---| "TERMINAL_CREATE_REQUESTED"
---| "TERMINAL_DELETE_REQUESTED"
---| "TERMINAL_RENAME_REQUESTED"
---| "TERMINAL_SELECT_REQUESTED"
---| "TERMINAL_READ_REQUESTED"
---| "TERMINAL_NEXT_REQUESTED"
---| "TERMINAL_PREV_REQUESTED"
---| "TERMINAL_MOVE_REQUESTED"
---| "TERMINAL_START_REQUESTED"
---| "TERMINAL_START_FAILED"
---| "TERMINAL_PROCESS_OPENED"
---| "TERMINAL_PROCESS_EXITED"
---| "SHELL_INTEGRATION_DETECTED"
---| "SHELL_PROMPT_STARTED"
---| "SHELL_COMMAND_INPUT_STARTED"
---| "SHELL_COMMAND_EXECUTED"
---| "SHELL_COMMAND_FINISHED"
---| "SHELL_COMMAND_ABORTED"
---| "TERMINAL_CWD_REPORTED"
---| "TERMINAL_TITLE_UPDATED"
---| "SHELL_BACKGROUND_JOB_NOTIFIED"
---| "TABPAGE_CLOSED"
---| "TERMINAL_BUFFER_WIPED_EXTERNALLY"
---| "SIDEBAR_WINDOW_CLOSED_EXTERNALLY"
---| "PANEL_WINDOW_CLOSED_EXTERNALLY"

---@alias tabterm.UICommandType
---| "MOUNT"
---| "UNMOUNT"
---| "RELAYOUT"
---| "RENDER_SIDEBAR"
---| "RENDER_PLACEHOLDER"
---| "START_TERMINAL"
---| "MOUNT_TERMINAL"
---| "DISPOSE_TERMINAL_BUFFERS"

---@class tabterm.EventBase
---@field tabpage integer?
---@field terminal_id string?

---@class tabterm.EventWinPayload
---@field winid integer?

---@class tabterm.EventCreateTerminalPayload
---@field spec tabterm.TerminalSpec|tabterm.TerminalSpecInput?
---@field to_index integer?

---@class tabterm.EventRenamePayload
---@field name_override string?

---@class tabterm.EventMovePayload
---@field to_index integer?

---@class tabterm.EventProcessOpenedPayload
---@field channel_id integer

---@class tabterm.EventStartFailedPayload
---@field message string?

---@class tabterm.EventProcessExitedPayload
---@field code integer?
---@field source tabterm.ResultSource?

---@class tabterm.EventIntegrationPayload
---@field integration tabterm.IntegrationKind

---@class tabterm.EventShellFinishedPayload
---@field code integer?

---@class tabterm.EventCwdPayload
---@field cwd string

---@class tabterm.EventTitlePayload
---@field title string

---@class tabterm.EventNotificationPayload
---@field kind tabterm.NotificationKind
---@field line string?

---@class tabterm.WorkspaceOpenRequestedEvent: tabterm.EventBase
---@field type "WORKSPACE_OPEN_REQUESTED"
---@field payload tabterm.EventWinPayload?

---@class tabterm.WorkspaceCloseRequestedEvent: tabterm.EventBase
---@field type "WORKSPACE_CLOSE_REQUESTED"

---@class tabterm.WorkspaceToggleRequestedEvent: tabterm.EventBase
---@field type "WORKSPACE_TOGGLE_REQUESTED"
---@field payload tabterm.EventWinPayload?

---@class tabterm.TerminalCreateRequestedEvent: tabterm.EventBase
---@field type "TERMINAL_CREATE_REQUESTED"
---@field payload tabterm.EventCreateTerminalPayload?

---@class tabterm.TerminalDeleteRequestedEvent: tabterm.EventBase
---@field type "TERMINAL_DELETE_REQUESTED"

---@class tabterm.TerminalRenameRequestedEvent: tabterm.EventBase
---@field type "TERMINAL_RENAME_REQUESTED"
---@field payload tabterm.EventRenamePayload?

---@class tabterm.TerminalSelectRequestedEvent: tabterm.EventBase
---@field type "TERMINAL_SELECT_REQUESTED"

---@class tabterm.TerminalReadRequestedEvent: tabterm.EventBase
---@field type "TERMINAL_READ_REQUESTED"

---@class tabterm.TerminalNextRequestedEvent: tabterm.EventBase
---@field type "TERMINAL_NEXT_REQUESTED"

---@class tabterm.TerminalPrevRequestedEvent: tabterm.EventBase
---@field type "TERMINAL_PREV_REQUESTED"

---@class tabterm.TerminalMoveRequestedEvent: tabterm.EventBase
---@field type "TERMINAL_MOVE_REQUESTED"
---@field payload tabterm.EventMovePayload?

---@class tabterm.TerminalStartRequestedEvent: tabterm.EventBase
---@field type "TERMINAL_START_REQUESTED"

---@class tabterm.TerminalStartFailedEvent: tabterm.EventBase
---@field type "TERMINAL_START_FAILED"
---@field payload tabterm.EventStartFailedPayload?

---@class tabterm.TerminalProcessOpenedEvent: tabterm.EventBase
---@field type "TERMINAL_PROCESS_OPENED"
---@field payload tabterm.EventProcessOpenedPayload

---@class tabterm.TerminalProcessExitedEvent: tabterm.EventBase
---@field type "TERMINAL_PROCESS_EXITED"
---@field payload tabterm.EventProcessExitedPayload?

---@class tabterm.ShellIntegrationDetectedEvent: tabterm.EventBase
---@field type "SHELL_INTEGRATION_DETECTED"
---@field payload tabterm.EventIntegrationPayload

---@class tabterm.ShellPromptStartedEvent: tabterm.EventBase
---@field type "SHELL_PROMPT_STARTED"

---@class tabterm.ShellCommandInputStartedEvent: tabterm.EventBase
---@field type "SHELL_COMMAND_INPUT_STARTED"

---@class tabterm.ShellCommandExecutedEvent: tabterm.EventBase
---@field type "SHELL_COMMAND_EXECUTED"

---@class tabterm.ShellCommandFinishedEvent: tabterm.EventBase
---@field type "SHELL_COMMAND_FINISHED"
---@field payload tabterm.EventShellFinishedPayload

---@class tabterm.ShellCommandAbortedEvent: tabterm.EventBase
---@field type "SHELL_COMMAND_ABORTED"

---@class tabterm.TerminalCwdReportedEvent: tabterm.EventBase
---@field type "TERMINAL_CWD_REPORTED"
---@field payload tabterm.EventCwdPayload

---@class tabterm.TerminalTitleUpdatedEvent: tabterm.EventBase
---@field type "TERMINAL_TITLE_UPDATED"
---@field payload tabterm.EventTitlePayload

---@class tabterm.ShellBackgroundJobNotifiedEvent: tabterm.EventBase
---@field type "SHELL_BACKGROUND_JOB_NOTIFIED"
---@field payload tabterm.EventNotificationPayload?

---@class tabterm.TabpageClosedEvent: tabterm.EventBase
---@field type "TABPAGE_CLOSED"

---@class tabterm.TerminalBufferWipedExternallyEvent: tabterm.EventBase
---@field type "TERMINAL_BUFFER_WIPED_EXTERNALLY"

---@class tabterm.SidebarWindowClosedExternallyEvent: tabterm.EventBase
---@field type "SIDEBAR_WINDOW_CLOSED_EXTERNALLY"

---@class tabterm.PanelWindowClosedExternallyEvent: tabterm.EventBase
---@field type "PANEL_WINDOW_CLOSED_EXTERNALLY"

---@alias tabterm.Event
---| tabterm.WorkspaceOpenRequestedEvent
---| tabterm.WorkspaceCloseRequestedEvent
---| tabterm.WorkspaceToggleRequestedEvent
---| tabterm.TerminalCreateRequestedEvent
---| tabterm.TerminalDeleteRequestedEvent
---| tabterm.TerminalRenameRequestedEvent
---| tabterm.TerminalSelectRequestedEvent
---| tabterm.TerminalReadRequestedEvent
---| tabterm.TerminalNextRequestedEvent
---| tabterm.TerminalPrevRequestedEvent
---| tabterm.TerminalMoveRequestedEvent
---| tabterm.TerminalStartRequestedEvent
---| tabterm.TerminalStartFailedEvent
---| tabterm.TerminalProcessOpenedEvent
---| tabterm.TerminalProcessExitedEvent
---| tabterm.ShellIntegrationDetectedEvent
---| tabterm.ShellPromptStartedEvent
---| tabterm.ShellCommandInputStartedEvent
---| tabterm.ShellCommandExecutedEvent
---| tabterm.ShellCommandFinishedEvent
---| tabterm.ShellCommandAbortedEvent
---| tabterm.TerminalCwdReportedEvent
---| tabterm.TerminalTitleUpdatedEvent
---| tabterm.ShellBackgroundJobNotifiedEvent
---| tabterm.TabpageClosedEvent
---| tabterm.TerminalBufferWipedExternallyEvent
---| tabterm.SidebarWindowClosedExternallyEvent
---| tabterm.PanelWindowClosedExternallyEvent

---@class tabterm.UICommandBase

---@class tabterm.MountCommandArgs
---@field tabpage integer

---@class tabterm.UnmountCommandArgs
---@field tabpage integer

---@class tabterm.RelayoutCommandArgs
---@field tabpage integer

---@class tabterm.RenderSidebarCommandArgs
---@field tabpage integer
---@field workspace tabterm.Workspace

---@class tabterm.RenderPlaceholderCommandArgs
---@field tabpage integer
---@field workspace tabterm.Workspace

---@class tabterm.StartTerminalCommandArgs
---@field tabpage integer
---@field terminal_id string
---@field terminal tabterm.Terminal

---@class tabterm.MountTerminalCommandArgs
---@field tabpage integer
---@field terminal_id string
---@field terminal tabterm.Terminal
---@field bufnr integer

---@class tabterm.DisposeTerminalBuffersCommandArgs
---@field terminal_refs tabterm.TerminalBufferRef[]

---@class tabterm.MountCommand: tabterm.UICommandBase
---@field [1] "MOUNT"
---@field [2] tabterm.MountCommandArgs

---@class tabterm.UnmountCommand: tabterm.UICommandBase
---@field [1] "UNMOUNT"
---@field [2] tabterm.UnmountCommandArgs

---@class tabterm.RelayoutCommand: tabterm.UICommandBase
---@field [1] "RELAYOUT"
---@field [2] tabterm.RelayoutCommandArgs

---@class tabterm.RenderSidebarCommand: tabterm.UICommandBase
---@field [1] "RENDER_SIDEBAR"
---@field [2] tabterm.RenderSidebarCommandArgs

---@class tabterm.RenderPlaceholderCommand: tabterm.UICommandBase
---@field [1] "RENDER_PLACEHOLDER"
---@field [2] tabterm.RenderPlaceholderCommandArgs

---@class tabterm.StartTerminalCommand: tabterm.UICommandBase
---@field [1] "START_TERMINAL"
---@field [2] tabterm.StartTerminalCommandArgs

---@class tabterm.MountTerminalCommand: tabterm.UICommandBase
---@field [1] "MOUNT_TERMINAL"
---@field [2] tabterm.MountTerminalCommandArgs

---@class tabterm.DisposeTerminalBuffersCommand: tabterm.UICommandBase
---@field [1] "DISPOSE_TERMINAL_BUFFERS"
---@field [2] tabterm.DisposeTerminalBuffersCommandArgs

---@alias tabterm.UICommand
---| tabterm.MountCommand
---| tabterm.UnmountCommand
---| tabterm.RelayoutCommand
---| tabterm.RenderSidebarCommand
---| tabterm.RenderPlaceholderCommand
---| tabterm.StartTerminalCommand
---| tabterm.MountTerminalCommand
---| tabterm.DisposeTerminalBuffersCommand

local M = {
	events = {
		WORKSPACE_OPEN_REQUESTED = "WORKSPACE_OPEN_REQUESTED",
		WORKSPACE_CLOSE_REQUESTED = "WORKSPACE_CLOSE_REQUESTED",
		WORKSPACE_TOGGLE_REQUESTED = "WORKSPACE_TOGGLE_REQUESTED",

		TERMINAL_CREATE_REQUESTED = "TERMINAL_CREATE_REQUESTED",
		TERMINAL_DELETE_REQUESTED = "TERMINAL_DELETE_REQUESTED",
		TERMINAL_RENAME_REQUESTED = "TERMINAL_RENAME_REQUESTED",
		TERMINAL_SELECT_REQUESTED = "TERMINAL_SELECT_REQUESTED",
		TERMINAL_READ_REQUESTED = "TERMINAL_READ_REQUESTED",
		TERMINAL_NEXT_REQUESTED = "TERMINAL_NEXT_REQUESTED",
		TERMINAL_PREV_REQUESTED = "TERMINAL_PREV_REQUESTED",
		TERMINAL_MOVE_REQUESTED = "TERMINAL_MOVE_REQUESTED",
		TERMINAL_START_REQUESTED = "TERMINAL_START_REQUESTED",
		TERMINAL_START_FAILED = "TERMINAL_START_FAILED",

		TERMINAL_PROCESS_OPENED = "TERMINAL_PROCESS_OPENED",
		TERMINAL_PROCESS_EXITED = "TERMINAL_PROCESS_EXITED",

		SHELL_INTEGRATION_DETECTED = "SHELL_INTEGRATION_DETECTED",
		SHELL_PROMPT_STARTED = "SHELL_PROMPT_STARTED",
		SHELL_COMMAND_INPUT_STARTED = "SHELL_COMMAND_INPUT_STARTED",
		SHELL_COMMAND_EXECUTED = "SHELL_COMMAND_EXECUTED",
		SHELL_COMMAND_FINISHED = "SHELL_COMMAND_FINISHED",
		SHELL_COMMAND_ABORTED = "SHELL_COMMAND_ABORTED",

		TERMINAL_CWD_REPORTED = "TERMINAL_CWD_REPORTED",
		TERMINAL_TITLE_UPDATED = "TERMINAL_TITLE_UPDATED",
		SHELL_BACKGROUND_JOB_NOTIFIED = "SHELL_BACKGROUND_JOB_NOTIFIED",

		TABPAGE_CLOSED = "TABPAGE_CLOSED",
		TERMINAL_BUFFER_WIPED_EXTERNALLY = "TERMINAL_BUFFER_WIPED_EXTERNALLY",
		SIDEBAR_WINDOW_CLOSED_EXTERNALLY = "SIDEBAR_WINDOW_CLOSED_EXTERNALLY",
		PANEL_WINDOW_CLOSED_EXTERNALLY = "PANEL_WINDOW_CLOSED_EXTERNALLY",
	},

	ui_commands = {
		MOUNT = "MOUNT",
		UNMOUNT = "UNMOUNT",
		RELAYOUT = "RELAYOUT",
		RENDER_SIDEBAR = "RENDER_SIDEBAR",
		RENDER_PLACEHOLDER = "RENDER_PLACEHOLDER",
		START_TERMINAL = "START_TERMINAL",
		MOUNT_TERMINAL = "MOUNT_TERMINAL",
		DISPOSE_TERMINAL_BUFFERS = "DISPOSE_TERMINAL_BUFFERS",
	},
}

return M

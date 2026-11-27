local WorldEditorAccess = {}
local openEditor, closeEditor, confirmExit

function WorldEditorAccess.register(open, close, confirm)
	openEditor, closeEditor, confirmExit = open, close, confirm
end

function WorldEditorAccess.open(parent)
	if not openEditor then return false, "The Battle Royale World Editor is unavailable in this session." end
	return openEditor(parent)
end

function WorldEditorAccess.close()
	if closeEditor then closeEditor() end
end

function WorldEditorAccess.confirmExit(proceed)
	if confirmExit then confirmExit(proceed) else proceed() end
end

return WorldEditorAccess

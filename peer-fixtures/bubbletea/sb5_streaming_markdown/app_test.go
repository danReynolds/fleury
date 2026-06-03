package main

import "testing"

func TestStreamingMarkdownCopyLinkPolicyAndSafety(t *testing.T) {
	model := NewSb5StreamingMarkdownModel(defaultColumns, defaultRows)
	fixture := MarkdownFixture{Seed: 1}
	chunkCount := markdownChunkCountFor(1_000)

	for index := range chunkCount {
		model = model.Apply(appendChunkMsg{RawChunk: fixture.Chunk(index)})
	}
	model = model.Apply(selectFinalBlockMsg{})
	model = model.Apply(copyBlockMsg{})
	state := model.StateSnapshot()

	if state.ChunkCount != chunkCount {
		t.Fatalf("chunk count = %d, want %d", state.ChunkCount, chunkCount)
	}
	if state.BlockCount == 0 {
		t.Fatalf("block count is zero")
	}
	if state.HeadingCount == 0 {
		t.Fatalf("heading count is zero")
	}
	if state.ListItemCount == 0 {
		t.Fatalf("list item count is zero")
	}
	if state.LinkCount == 0 {
		t.Fatalf("link count is zero")
	}
	if state.UnsafeLinkCount == 0 {
		t.Fatalf("unsafe link count is zero")
	}
	if state.CodeBlockCount == 0 {
		t.Fatalf("code block count is zero")
	}
	if state.CodeLineCount == 0 {
		t.Fatalf("code line count is zero")
	}
	if state.SelectedBlockIndex != state.BlockCount-1 {
		t.Fatalf("selected block index = %d, block count = %d", state.SelectedBlockIndex, state.BlockCount)
	}
	if state.CopiedByteCount == 0 {
		t.Fatalf("copied byte count is zero")
	}
	if state.SanitizedChunkCount == 0 {
		t.Fatalf("sanitized chunk count is zero")
	}
	if !state.UnsafeLinksHaveVisibleFallback {
		t.Fatalf("unsafe links do not have visible fallback")
	}
	if state.UnsafeArtifactLeakCount != 0 {
		t.Fatalf("unsafe artifact leak count = %d", state.UnsafeArtifactLeakCount)
	}
	if unsafeCountText(model.LastCopiedText()) != 0 {
		t.Fatalf("copied block leaked unsafe content: %q", model.LastCopiedText())
	}
	if model.lastRenderError != "" {
		t.Fatalf("render error: %s", model.lastRenderError)
	}
}

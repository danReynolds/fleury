/// Fleury's explicitly unstable, platform-neutral remote wire.
///
/// This library exposes the frame protocol, codecs, and transport contracts
/// used by first-party browser and agent peers that ship in lockstep with
/// Fleury. It is correctness-tested, but it is not a semver-stable integration
/// surface: frame shapes and negotiation rules may change between releases.
///
/// Most platform hosts should use `fleury_host.dart`. A peer that deliberately
/// speaks this wire must follow `docs/implementation/wire-protocol.md` and use a
/// matching Fleury build.
library;

export 'src/runtime/remote_surface_sink.dart' show RemoteClipboardStatus;
export 'src/remote/remote_protocol.dart'
    show
        ByeFrame,
        CaretFrame,
        ClipboardResultFrame,
        ClipboardWriteFrame,
        DebugRequestFrame,
        DebugResponseFrame,
        FrameDecoder,
        FrameType,
        InitFrame,
        InlineImageFrame,
        InputEventFrame,
        InputFrame,
        OutputFrame,
        PlanFrame,
        RemoteFrame,
        RemoteProtocolException,
        ResizeFrame,
        SemanticActionFrame,
        SemanticActionResultFrame,
        SemanticsFrame,
        defaultMaxRemoteFramePayloadLength,
        maxRemoteControlFramePayloadLength,
        maxRemoteDocumentFramePayloadLength,
        maxRemoteImageFramePayloadLength,
        maxRemoteInputFramePayloadLength,
        maxRemoteDebugResponseJsonLength,
        encodeFrame,
        remoteFramePayloadLimit,
        remoteProtocolVersion,
        semanticActionTargetTokenProtocolVersion,
        serveSessionBusyCloseCode,
        serveSessionLimitCloseCode;
export 'src/remote/inline_image_cache.dart'
    show
        InlineImageCacheLedger,
        InlineImageCachePolicy,
        defaultInlineImageCachePolicy;
export 'src/remote/remote_codec.dart'
    show
        ImagePlacement,
        RemoteCodecException,
        RemotePatchRun,
        RemotePlan,
        RemoteRowPatch,
        applyRemotePlanToBuffer,
        buildRemotePlan,
        decodeInputEvent,
        decodeRemotePlan,
        decodeSemanticAction,
        encodeInputEvent,
        encodeRemotePlan,
        encodeSemanticAction,
        maxRemoteSemanticNodeIdBytes;
export 'src/remote/remote_semantics.dart'
    show
        SemanticWireDelta,
        SemanticsWireDecoder,
        SemanticsWireEncoder,
        maxSemanticTreeDepth,
        maxSemanticWireEdges,
        maxSemanticWireNodes,
        semanticsWireVersion;
export 'src/remote/remote_transport.dart'
    show RemoteFrameTransport, SynchronousSendTransport;

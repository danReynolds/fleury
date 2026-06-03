/// Git integration helpers for Fleury apps.
///
/// This package is intentionally a small integration proof, not a Git process
/// runner. Apps own repository discovery, refresh, mutation, and lifecycle;
/// the package contributes typed state, commands, status, theme defaults, and
/// widgets through Fleury's app-extension seam.
library;

export 'src/git_extension.dart'
    show
        FleuryGitExtension,
        GitCommandCallback,
        GitRepositoryDataSource,
        GitRepositorySnapshot,
        GitStatusPanel,
        StaticGitRepositoryDataSource,
        gitCommitCommandId,
        gitOpenChangesCommandId,
        gitPushCommandId,
        gitRefreshCommandId;

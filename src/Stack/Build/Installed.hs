{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot   #-}
{-# LANGUAGE OverloadedStrings     #-}

{-|
Module      : Stack.Build.Installed
Description : Determine which packages are already installed.
License     : BSD-3-Clause

Determine which packages are already installed.
-}

module Stack.Build.Installed
  ( getInstalled
  , toInstallMap
  ) where

import           Data.Conduit ( ZipSink (..), getZipSink )
import qualified Data.Conduit.List as CL
import qualified Data.Set as Set
import qualified Data.Map.Strict as Map
import           Stack.Build.Cache ( getInstalledExes )
import           Stack.Constants ( wiredInPackages )
import           Stack.PackageDump
                   ( conduitDumpPackage, ghcPkgDump, pruneDeps )
import           Stack.Prelude
import           Stack.SourceMap ( getPLIVersion, loadVersion )
import           Stack.Types.CompilerPaths ( getGhcPkgExe )
import           Stack.Types.DumpPackage
                   ( DumpPackage (..), SublibDump (..), sublibParentPkgId )
import           Stack.Types.EnvConfig
                    ( HasEnvConfig, packageDatabaseDeps, packageDatabaseExtra
                    , packageDatabaseLocal
                    )
import           Stack.Types.GhcPkgId ( GhcPkgId )
import           Stack.Types.Installed
                   ( InstallLocation (..), InstallMap, Installed (..)
                   , InstalledLibraryInfo (..), InstalledMap
                   , InstalledPackageLocation (..), PackageDatabase (..)
                   , PackageDbVariety (..), toPackageDbVariety
                   )
import           Stack.Types.SourceMap
                   ( DepPackage (..), ProjectPackage (..), SourceMap (..) )

-- | For the given t'SourceMap', yield a dictionary of package names for a
-- project's packages and dependencies, and pairs of their relevant database
-- (write-only or mutable) and package versions.
toInstallMap :: MonadIO m => SourceMap -> m InstallMap
toInstallMap sourceMap = do
  projectInstalls <-
    for sourceMap.project $ \pp -> do
      version <- loadVersion pp.projectCommon
      pure (Local, version)
  depInstalls <-
    for sourceMap.deps $ \dp ->
      case dp.location of
        PLImmutable pli -> pure (Snap, getPLIVersion pli)
        PLMutable _ -> do
          version <- loadVersion dp.depCommon
          pure (Local, version)
  pure $ projectInstalls <> depInstalls

-- | Returns the new InstalledMap and all of the locally registered packages.
getInstalled ::
     HasEnvConfig env
  => InstallMap -- ^ does not contain any installed information
  -> RIO env
       ( InstalledMap
       , [DumpPackage] -- globally installed
       , [DumpPackage] -- snapshot installed
       , [DumpPackage] -- locally installed
       )
getInstalled {-opts-} installMap = do
  logDebug "Finding out which packages are already installed"
  snapDBPath <- packageDatabaseDeps
  localDBPath <- packageDatabaseLocal
  extraDBPaths <- packageDatabaseExtra

  let loadDatabase' = loadDatabase {-opts mcache-} installMap

  (installedLibs0, globalDumpPkgs) <- loadDatabase' GlobalPkgDb []
  (installedLibs1, _extraInstalled) <-
    foldM (\lhs' pkgdb ->
      loadDatabase' (UserPkgDb ExtraPkgDb pkgdb) (fst lhs')
      ) (installedLibs0, globalDumpPkgs) extraDBPaths
  (installedLibs2, snapshotDumpPkgs) <-
    loadDatabase' (UserPkgDb (InstalledTo Snap) snapDBPath) installedLibs1
  (installedLibs3, localDumpPkgs) <-
    loadDatabase' (UserPkgDb (InstalledTo Local) localDBPath) installedLibs2
  let installedLibs =
        foldr' gatherAndTransformSubLoadHelper mempty installedLibs3

  -- Add in the executables that are installed, making sure to only trust a
  -- listed installation under the right circumstances (see below)
  let exesToSM loc = Map.unions . map (exeToSM loc)
      exeToSM loc (PackageIdentifier name version) =
        case Map.lookup name installMap of
          -- Doesn't conflict with anything, so that's OK
          Nothing -> m
          Just (iLoc, iVersion)
            -- Not the version we want, ignore it
            | version /= iVersion || mismatchingLoc loc iLoc -> Map.empty
            | otherwise -> m
       where
        m = Map.singleton name (loc, Executable $ PackageIdentifier name version)
        mismatchingLoc installed target
          | target == installed = False
          | installed == Local = False -- snapshot dependency could end up
                                       -- in a local install as being mutable
          | otherwise = True
  exesSnap <- getInstalledExes Snap
  exesLocal <- getInstalledExes Local
  let installedMap = Map.unions
        [ exesToSM Local exesLocal
        , exesToSM Snap exesSnap
        , installedLibs
        ]

  pure ( installedMap
       , globalDumpPkgs
       , snapshotDumpPkgs
       , localDumpPkgs
       )

-- | Outputs both the modified InstalledMap and the Set of all installed
-- packages in this database
--
-- The goal is to ascertain that the dependencies for a package are present,
-- that it has profiling if necessary, and that it matches the version and
-- location needed by the SourceMap.
loadDatabase ::
     forall env. HasEnvConfig env
  => InstallMap
     -- ^ to determine which installed things we should include
  -> PackageDatabase
     -- ^ package database.
  -> [LoadHelper]
     -- ^ from parent databases
  -> RIO env ([LoadHelper], [DumpPackage])
loadDatabase installMap db lhs0 = do
  pkgexe <- getGhcPkgExe
  (lhs1', dps) <- ghcPkgDump pkgexe pkgDb $ conduitDumpPackage .| sink
  lhs1 <- mapMaybeM processLoadResult lhs1'
  let lhs = pruneDeps id (.ghcPkgId) (.depsGhcPkgId) const (lhs0 ++ lhs1)
  pure (map (\lh -> lh { depsGhcPkgId = [] }) $ Map.elems lhs, dps)
 where
  pkgDb = case db of
    GlobalPkgDb -> []
    UserPkgDb _ fp -> [fp]

  sinkDP =  CL.map (isAllowed installMap db' &&& toLoadHelper db')
         .| CL.consume
   where
    db' = toPackageDbVariety db
  sink =   getZipSink $ (,)
       <$> ZipSink sinkDP
       <*> ZipSink CL.consume

  processLoadResult :: (Allowed, LoadHelper) -> RIO env (Maybe LoadHelper)
  processLoadResult (Allowed, lh) = pure (Just lh)
  processLoadResult (reason, lh) = do
    logDebug $
         "Ignoring package "
      <> fromPackageName (fst lh.pair)
      <> case db of
           GlobalPkgDb -> mempty
           UserPkgDb loc fp -> ", from " <> displayShow (loc, fp) <> ","
      <> " due to"
      <> case reason of
           UnknownPkg -> " it being unknown to the snapshot or extra-deps."
           WrongLocation db' loc ->
             " wrong location: " <> displayShow (db', loc)
           WrongVersion actual wanted ->
                " wanting version "
            <> fromString (versionString wanted)
            <> " instead of "
            <> fromString (versionString actual)
    pure Nothing

-- | Type representing results of 'isAllowed'.
data Allowed
  = Allowed
    -- ^ The installed package can be included in the set of relevant installed
    -- packages.
  | UnknownPkg
    -- ^ The installed package cannot be included in the set of relevant
    -- installed packages because the package is unknown.
  | WrongLocation PackageDbVariety InstallLocation
    -- ^ The installed package cannot be included in the set of relevant
    -- installed packages because the package is in the wrong package database.
  | WrongVersion Version Version
    -- ^ The installed package cannot be included in the set of relevant
    -- installed packages because the package has the wrong version.
  deriving (Eq, Show)

-- | Check if an installed package can be included in the set of relevant
-- installed packages or not, based on the package selections made by the user.
-- This does not perform any dirtiness or flag change checks.
isAllowed ::
     InstallMap
  -> PackageDbVariety
     -- ^ The package database providing the installed package.
  -> DumpPackage
     -- ^ The installed package to check.
  -> Allowed
isAllowed installMap pkgDb dp = case Map.lookup name installMap of
  Nothing ->
    -- If the sourceMap has nothing to say about this package,
    -- check if it represents a sub-library first
    -- See: https://github.com/commercialhaskell/stack/issues/3899
    case sublibParentPkgId dp of
      Just (PackageIdentifier parentLibName version') ->
        case Map.lookup parentLibName installMap of
          Nothing -> checkNotFound
          Just instInfo
            | version' == version -> checkFound instInfo
            | otherwise -> checkNotFound -- different versions
      Nothing -> checkNotFound
  Just pii -> checkFound pii
 where
  PackageIdentifier name version = dp.packageIdent
  -- Ensure that the installed location matches where the sourceMap says it
  -- should be installed.
  checkLocation Snap =
     -- snapshot deps could become mutable after getting any mutable dependency.
    True
  checkLocation Local = case pkgDb of
    GlobalDb -> False
    -- 'locally' installed snapshot packages can come from 'extra' package
    -- databases.
    ExtraDb -> True
    WriteOnlyDb -> False
    MutableDb -> True
  -- Check if an installed package is allowed if it is found in the sourceMap.
  checkFound (installLoc, installVer)
    | not (checkLocation installLoc) = WrongLocation pkgDb installLoc
    | version /= installVer = WrongVersion version installVer
    | otherwise = Allowed
  -- Check if an installed package is allowed if it is not found in the
  -- sourceMap.
  checkNotFound = case pkgDb of
    -- The sourceMap has nothing to say about this global package, so we can use
    -- it.
    GlobalDb -> Allowed
    ExtraDb -> Allowed
    -- For non-global packages, don't include unknown packages.
    -- See: https://github.com/commercialhaskell/stack/issues/292
    WriteOnlyDb -> UnknownPkg
    MutableDb -> UnknownPkg

-- | Type representing certain information about an installed package.
data LoadHelper = LoadHelper
  { ghcPkgId :: !GhcPkgId
    -- ^ The package's id.
  , subLibDump :: !(Maybe SublibDump)
  , depsGhcPkgId :: ![GhcPkgId]
    -- ^ Unless the package's name is that of a 'wired-in' package, a list of
    -- the ids of the installed packages that are the package's dependencies.
  , pair :: !(PackageName, (InstallLocation, Installed))
    -- ^ A pair of (a) the package's name and (b) a pair of the relevant
    -- database (write-only or mutable) and information about the library
    -- installed.
  }
  deriving Show

toLoadHelper :: PackageDbVariety -> DumpPackage -> LoadHelper
toLoadHelper pkgDb dp = LoadHelper
  { ghcPkgId
  , depsGhcPkgId
  , subLibDump = dp.sublib
  , pair
  }
 where
  ghcPkgId = dp.ghcPkgId
  ident@(PackageIdentifier name _) = dp.packageIdent
  depsGhcPkgId =
    -- We always want to consider the wired in packages as having all of their
    -- dependencies installed, since we have no ability to reinstall them. This
    -- is especially important for using different minor versions of GHC, where
    -- the dependencies of wired-in packages may change slightly and therefore
    -- not match the snapshot.
    if name `Set.member` wiredInPackages
      then []
      else dp.depends
  installedLibInfo = InstalledLibraryInfo ghcPkgId (Right <$> dp.license) mempty

  toInstallLocation :: PackageDbVariety -> InstallLocation
  toInstallLocation GlobalDb = Snap
  toInstallLocation ExtraDb = Snap
  toInstallLocation WriteOnlyDb = Snap
  toInstallLocation MutableDb = Local

  pair = (name, (toInstallLocation pkgDb, Library ident installedLibInfo))

-- | This is where sublibraries and main libraries are assembled into a single
-- entity Installed package, where all ghcPkgId live.
gatherAndTransformSubLoadHelper ::
     LoadHelper
  -> Map PackageName (InstallLocation, Installed)
  -> Map PackageName (InstallLocation, Installed)
gatherAndTransformSubLoadHelper lh =
  Map.insertWith onPreviousLoadHelper key value
 where
  -- Here we assume that both have the same location which already was a prior
  -- assumption in Stack.
  onPreviousLoadHelper
      (pLoc, Library pn incomingLibInfo)
      (_, Library _ existingLibInfo)
    = ( pLoc
      , Library pn existingLibInfo
          { subLib = Map.union
              incomingLibInfo.subLib
              existingLibInfo.subLib
          , ghcPkgId = if isJust lh.subLibDump
                      then existingLibInfo.ghcPkgId
                      else incomingLibInfo.ghcPkgId
          }
      )
  onPreviousLoadHelper newVal _oldVal = newVal
  (key, value) = case lh.subLibDump of
    Nothing -> (rawPackageName, rawValue)
    Just sd -> (sd.packageName, updateAsSublib sd <$> rawValue)
  (rawPackageName, rawValue) = lh.pair
  updateAsSublib
      sd
      (Library (PackageIdentifier _sublibMungedPackageName version) libInfo)
    = Library
        (PackageIdentifier key version)
        libInfo { subLib = Map.singleton sd.libraryName libInfo.ghcPkgId }
  updateAsSublib _ v = v

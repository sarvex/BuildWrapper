{-# LANGUAGE TypeSynonymInstances,OverloadedStrings #-}
-- |
-- Module      : Language.Haskell.BuildWrapper.Src
-- Author      : JP Moresmau
-- Copyright   : (c) JP Moresmau 2011
-- License     : BSD3
-- 
-- Maintainer  : jpmoresmau@gmail.com
-- Stability   : beta
-- Portability : portable
-- 
-- Use haskell-src-exts to get a module outline
module Language.Haskell.BuildWrapper.Src where

import Language.Haskell.BuildWrapper.Base

import Language.Haskell.Exts.Annotated

import qualified Data.Map as DM

import qualified Data.Text as T

-- | get the AST
getHSEAST :: String -- ^ input text
        -> [String] -- ^ options
        -> IO (ParseResult (Module SrcSpanInfo, [Comment]))
getHSEAST input options=do
        let exts=map classifyExtension options
        let extsFull=if "-fglasgow-exts" `elem` options
                then exts ++ glasgowExts
                else exts
        -- fixities necessary (see http://trac.haskell.org/haskell-src-exts/ticket/189 and https://sourceforge.net/projects/eclipsefp/forums/forum/371922/topic/4808590)
        let parseMode=defaultParseMode {extensions=extsFull,ignoreLinePragmas=False,ignoreLanguagePragmas=False,fixities = Just baseFixities} 
        return $ parseFileContentsWithComments parseMode input

-- | get the ouline from the AST        
getHSEOutline :: (Module SrcSpanInfo, [Comment]) -- ^ the commented AST (even though we ignore comments now)
        -> [OutlineDef]
getHSEOutline (Module _ _ _ _ decls,_)=concatMap declOutline decls
        where 
                declOutline :: Decl SrcSpanInfo -> [OutlineDef]
                declOutline (DataFamDecl l _ h _) = [mkOutlineDef (headDecl h) [Data,Family] (makeSpan l)]
                declOutline (DataInsDecl l _ t cons _) = [mkOutlineDefWithChildren (typeDecl t) [Data,Instance] (makeSpan l) (map qualConDeclOutline cons)]
                --declOutline (GDataInsDecl l _ t cons _) = [OutlineDef (typeDecl t) [Data,Instance] (makeSpan l) (map qualConDeclOutline cons)]
                declOutline (DataDecl l _ _ h cons _) = [mkOutlineDefWithChildren (headDecl h) [Data] (makeSpan l) (map qualConDeclOutline cons)]
                --declOutline (GDataDecl l _ _ h cons _) = [OutlineDef (headDecl h) [Data] (makeSpan l) (map qualConDeclOutline cons)]
                declOutline (TypeFamDecl l h _) = [mkOutlineDef (headDecl h) [Type,Family] (makeSpan l)]
                declOutline (TypeInsDecl l t1 _) = [mkOutlineDef (typeDecl t1) [Type,Instance] (makeSpan l)] -- ++ " "++(typeDecl t2)
                declOutline (TypeDecl l h t) = [OutlineDef (headDecl h) [Type] (makeSpan l) [] (Just $ typeDecl t)]
                declOutline (ClassDecl l _ h _ cdecls) = [mkOutlineDefWithChildren (headDecl h) [Class] (makeSpan l) (maybe [] (concatMap classDecl) cdecls)]
                declOutline (FunBind l matches) = let
                        n=matchDecl $ head matches
                        in [OutlineDef n [Function] (makeSpan l) [] (DM.lookup n typeMap)]
                declOutline (PatBind l (PVar _ n) _ _ _)=let
                        nd=nameDecl n
                        in [OutlineDef nd [Function] (makeSpan l)  [] (DM.lookup nd typeMap)]
                declOutline (InstDecl l _ h idecls)=[mkOutlineDefWithChildren (iheadDecl h) [Instance] (makeSpan l) (maybe [] (concatMap instDecl) idecls)]
                declOutline (SpliceDecl l e)=[mkOutlineDef (spliceDecl e) [Splice] (makeSpan l)]
                declOutline _ = []
                qualConDeclOutline :: QualConDecl SrcSpanInfo-> OutlineDef
                qualConDeclOutline (QualConDecl l _ _ con)=let
                        (n,defs)=conDecl con
                        in mkOutlineDefWithChildren n [Constructor] (makeSpan l) defs
                declOutlineInClass :: Decl SrcSpanInfo -> [OutlineDef]
                declOutlineInClass (TypeSig l ns _)=map (\n->mkOutlineDef (nameDecl n) [Function] (makeSpan l)) ns
                declOutlineInClass o=declOutline o
                headDecl :: DeclHead  a -> T.Text
                headDecl (DHead _ n  _)=nameDecl n
                headDecl (DHInfix _ _ n _)=nameDecl n
                headDecl (DHParen _ h)=headDecl h
                typeDecl :: Type a -> T.Text
--                typeDecl (TyForall _ mb mc t)=typeDecl t
--                typeDecl (TyVar _ n )=nameDecl n
--                typeDecl (TyCon _ qn )=qnameDecl qn
--                typeDecl (TyList _ t )=T.concat  ["[", typeDecl t, "]"]
--                typeDecl (TyParen _ t )=typeDecl t
--                typeDecl (TyApp _ t1 t2)=T.concat  [typeDecl t1, " ", typeDecl t2]
--                typeDecl (TyFun _ t1 t2)=T.concat  [typeDecl t1, " -> ", typeDecl t2]
                typeDecl = T.pack . prettyPrint 
                matchDecl :: Match a -> T.Text
                matchDecl (Match _ n _ _ _)=nameDecl n     
                matchDecl (InfixMatch _ _ n _ _ _)=nameDecl n    
                iheadDecl :: InstHead a -> T.Text
                iheadDecl (IHead _ qn ts)= T.concat  [qnameDecl qn, " ", T.intercalate " " (map typeDecl ts)]
                iheadDecl (IHInfix _ t1 qn t2)= T.concat  [typeDecl t1, " ", qnameDecl qn, " ", typeDecl t2]
                iheadDecl (IHParen _ i)=iheadDecl i
                conDecl :: ConDecl SrcSpanInfo -> (T.Text,[OutlineDef])
                conDecl (ConDecl _ n _)=(nameDecl n,[])
                conDecl (InfixConDecl _ _ n _)=(nameDecl n,[])
                conDecl (RecDecl _ n fields)=(nameDecl n,concatMap fieldDecl fields)
                fieldDecl :: FieldDecl SrcSpanInfo -> [OutlineDef]
                fieldDecl (FieldDecl l ns _)=map (\n->mkOutlineDef (nameDecl n) [Field] (makeSpan l)) ns
                classDecl :: ClassDecl SrcSpanInfo -> [OutlineDef]
                classDecl (ClsDecl _ d) = declOutlineInClass d
                classDecl _ = []
                instDecl :: InstDecl SrcSpanInfo -> [OutlineDef]
                instDecl (InsDecl _ d) = declOutlineInClass d
                instDecl _ = []
                spliceDecl :: Exp SrcSpanInfo -> T.Text
                spliceDecl (SpliceExp _ sp)= spliceName sp
                spliceDecl (App _ e1 _)=spliceDecl e1
                spliceDecl (Var _ qn)=qnameDecl qn
                spliceDecl _ = ""
                spliceName :: Splice SrcSpanInfo -> T.Text
                spliceName (IdSplice _ n)=T.pack n
                spliceName (ParenSplice  _ e)=spliceDecl e
                -- | a type map name -> Type
                typeMap :: DM.Map T.Text T.Text
                typeMap = foldr buildTypeMap DM.empty decls
                buildTypeMap :: Decl SrcSpanInfo -> DM.Map T.Text T.Text -> DM.Map T.Text T.Text
                buildTypeMap (TypeSig _ ns t) m=let
                        td=typeDecl t
                        in if T.null td
                                then m
                                else foldr (\n2 m2->DM.insert (nameDecl n2) td m2) m ns 
                buildTypeMap _ m=m
getHSEOutline _ = []

-- | get the import/export declarations
getHSEImportExport :: (Module SrcSpanInfo, [Comment]) -- ^ the AST 
        -> ([ExportDef],[ImportDef])
getHSEImportExport (Module _ mhead _ imps _,_)=(headExp mhead,impDefs imps)
        where
                headExp :: Maybe (ModuleHead SrcSpanInfo) ->[ExportDef] 
                headExp (Just (ModuleHead  _ _ _ (Just (ExportSpecList _ exps))))=map expExp exps
                headExp _ = [] 
                expExp :: ExportSpec SrcSpanInfo -> ExportDef
                expExp (EVar l qn) = ExportDef (qnameDecl qn) IEVar (makeSpan l) []
                expExp (EAbs l qn) = ExportDef (qnameDecl qn) IEAbs (makeSpan l) []
                expExp (EThingAll l qn) = ExportDef (qnameDecl qn) IEThingAll (makeSpan l) []
                expExp (EThingWith l qn cns) = ExportDef (qnameDecl qn) IEThingWith (makeSpan l) (map cnameDecl cns)
                expExp (EModuleContents l mn) = ExportDef (mnnameDecl mn) IEModule (makeSpan l) []
                impDefs :: [ImportDecl SrcSpanInfo] -> [ImportDef]
                impDefs=map impDef
                impDef :: ImportDecl SrcSpanInfo -> ImportDef
                impDef (ImportDecl l m qual _ _ al specs)=ImportDef (mnnameDecl m) (makeSpan l) qual (hide specs) (alias al) (children specs)
                hide :: Maybe (ImportSpecList a)-> Bool
                hide  (Just (ImportSpecList _ b _))=b
                hide _=False
                alias :: Maybe (ModuleName a) -> T.Text
                alias (Just mn)=mnnameDecl mn
                alias Nothing =""
                children :: Maybe (ImportSpecList SrcSpanInfo) -> Maybe [ImportSpecDef]
                children (Just (ImportSpecList _ _ ss))=Just $ map child ss
                children Nothing = Nothing
                child :: ImportSpec SrcSpanInfo -> ImportSpecDef
                child (IVar l n)=ImportSpecDef (nameDecl n) IEVar (makeSpan l) []
                child (IAbs l n)=ImportSpecDef (nameDecl n) IEAbs (makeSpan l) []
                child (IThingAll l n) = ImportSpecDef (nameDecl n) IEThingAll (makeSpan l) []
                child (IThingWith l n cns) = ImportSpecDef (nameDecl n) IEThingWith (makeSpan l) (map cnameDecl cns)
getHSEImportExport _=([],[])                

nameDecl :: Name a -> T.Text
nameDecl (Ident _ s)=T.pack s
nameDecl (Symbol _ s)=T.pack s
cnameDecl :: CName a -> T.Text
cnameDecl (VarName _ s)=nameDecl s
cnameDecl (ConName _ s)=nameDecl s
qnameDecl :: QName a -> T.Text
qnameDecl (Qual _ _ n)=nameDecl n
qnameDecl (UnQual _ n)=nameDecl n
qnameDecl _ ="" 
mnnameDecl :: ModuleName a -> T.Text
mnnameDecl (ModuleName _ s)=T.pack s
 
-- | convert a HSE span into a buildwrapper span 
makeSpan :: SrcSpanInfo -> InFileSpan
makeSpan si=let
        sis=srcInfoSpan si
        (sl,sc)=srcSpanStart sis
        (el,ec)=srcSpanEnd sis      
        in   InFileSpan (InFileLoc sl sc) (InFileLoc el ec)
   
-- | all known extensions, as string   
knownExtensionNames :: [String]
knownExtensionNames = map show knownExtensions











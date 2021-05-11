(*
 * Copyright (c) 2021 ARATA Mizuki
 * This file is part of LunarML.
 *)
structure FSyntax = struct
type TyVar = USyntax.TyVar
type TyCon = USyntax.TyCon
datatype Ty = TyVar of TyVar
            | RecordType of (Syntax.Label * Ty) list
            | TyCon of Ty list * TyCon
            | FnType of Ty * Ty
            | ForallType of TyVar * Ty
datatype Pat = WildcardPat
             | SConPat of Syntax.SCon
             | VarPat of USyntax.VId * Ty
             | RecordPat of (Syntax.Label * Pat) list * bool
             | InstantiatedConPat of USyntax.LongVId * Pat option * Ty list
             | LayeredPat of USyntax.VId * Ty * Pat
datatype ConBind = ConBind of USyntax.VId * Ty option
datatype DatBind = DatBind of TyVar list * TyCon * ConBind list
datatype Exp = SConExp of Syntax.SCon
             | VarExp of USyntax.LongVId
             | RecordExp of (Syntax.Label * Exp) list
             | LetExp of Dec * Exp
             | AppExp of Exp * Exp
             | HandleExp of { body : Exp
                            , exnName : USyntax.VId
                            , handler : Exp
                            }
             | RaiseExp of SourcePos.span * Exp
             | IfThenElseExp of Exp * Exp * Exp
             | CaseExp of SourcePos.span * Exp * Ty * (Pat * Exp) list
             | FnExp of USyntax.VId * Ty * Exp
             | ProjectionExp of { label : Syntax.Label, recordTy : Ty, fieldTy : Ty }
             | TyAbsExp of TyVar * Exp
             | TyAppExp of Exp * Ty
             | RecordEqualityExp of (Syntax.Label * Exp) list
             | DataTagExp of Exp (* * TyCon *)
             | DataPayloadExp of Exp (* * USyntax.LongVId * TyCon *)
     and ValBind = SimpleBind of USyntax.VId * Ty * Exp
                 | TupleBind of (USyntax.VId * Ty) list * Exp
     and Dec = ValDec of ValBind
             | RecValDec of ValBind list
             | DatatypeDec of DatBind list
             | ExceptionDec of { conName : USyntax.VId, tagName : USyntax.VId, payloadTy : Ty option }
fun PairType(a, b) = RecordType [(Syntax.NumericLabel 1, a), (Syntax.NumericLabel 2, b)]
fun TupleExp xs = let fun doFields i nil = nil
                        | doFields i (x :: xs) = (Syntax.NumericLabel i, x) :: doFields (i + 1) xs
                  in RecordExp (doFields 1 xs)
                  end
fun AndalsoExp(a, b) = IfThenElseExp(a, b, VarExp(Syntax.MkQualified([], InitialEnv.VId_false)))
fun SimplifyingAndalsoExp(a as VarExp(Syntax.MkQualified([], vid)), b) = if vid = InitialEnv.VId_true then
                                                                             b
                                                                         else if vid = InitialEnv.VId_false then
                                                                             a
                                                                         else
                                                                             AndalsoExp(a, b)
  | SimplifyingAndalsoExp(a, b as VarExp(Syntax.MkQualified([], vid))) = if vid = InitialEnv.VId_true then
                                                                             a
                                                                         else
                                                                             AndalsoExp(a, b)
  | SimplifyingAndalsoExp(a, b) = AndalsoExp(a, b)

(* occurCheck : TyVar -> Ty -> bool *)
fun occurCheck tv =
    let fun check (TyVar tv') = USyntax.eqUTyVar(tv, tv')
          | check (RecordType xs) = List.exists (fn (label, ty) => check ty) xs
          | check (TyCon(tyargs, longtycon)) = List.exists check tyargs
          | check (FnType(ty1, ty2)) = check ty1 orelse check ty2
          | check (ForallType(tv', ty)) = if USyntax.eqUTyVar(tv, tv') then
                                              false
                                          else
                                              check ty
    in check
    end

(* substituteTy : TyVar * Ty -> Ty -> Ty *)
fun substituteTy (tv, replacement) =
    let fun go (ty as TyVar tv') = if USyntax.eqUTyVar(tv, tv') then
                                       replacement
                                   else
                                       ty
          | go (RecordType fields) = RecordType (Syntax.mapRecordRow go fields)
          | go (TyCon(tyargs, longtycon)) = TyCon(List.map go tyargs, longtycon)
          | go (FnType(ty1, ty2)) = FnType(go ty1, go ty2)
          | go (ty as ForallType(tv', ty')) = if USyntax.eqUTyVar(tv, tv') then
                                                  ty
                                              else if occurCheck tv' replacement then
                                                  (* TODO: generate fresh type variable *)
                                                  let val tv'' = raise Fail "FSyntax.substituteTy: not implemented yet"
                                                  in ForallType(tv'', go (substituteTy (tv', TyVar tv'') ty'))
                                                  end
                                              else
                                                  ForallType(tv', go ty')
    in go
    end

structure PrettyPrint = struct
val print_TyVar = USyntax.print_TyVar
val print_VId = USyntax.print_VId
val print_LongVId = USyntax.print_LongVId
val print_TyCon = USyntax.print_TyCon
fun print_Ty (TyVar x) = "TyVar(" ^ print_TyVar x ^ ")"
  | print_Ty (RecordType xs) = (case Syntax.extractTuple (1, xs) of
                                    NONE => "RecordType " ^ Syntax.print_list (Syntax.print_pair (Syntax.print_Label,print_Ty)) xs
                                  | SOME ys => "TupleType " ^ Syntax.print_list print_Ty ys
                               )
  | print_Ty (TyCon([],USyntax.MkTyCon("int", 0))) = "primTy_int"
  | print_Ty (TyCon([],USyntax.MkTyCon("word", 1))) = "primTy_word"
  | print_Ty (TyCon([],USyntax.MkTyCon("real", 2))) = "primTy_real"
  | print_Ty (TyCon([],USyntax.MkTyCon("string", 3))) = "primTy_string"
  | print_Ty (TyCon([],USyntax.MkTyCon("char", 4))) = "primTy_char"
  | print_Ty (TyCon([],USyntax.MkTyCon("exn", 5))) = "primTy_exn"
  | print_Ty (TyCon([],USyntax.MkTyCon("bool", 6))) = "primTy_bool"
  | print_Ty (TyCon(x,y)) = "TyCon(" ^ Syntax.print_list print_Ty x ^ "," ^ print_TyCon y ^ ")"
  | print_Ty (FnType(x,y)) = "FnType(" ^ print_Ty x ^ "," ^ print_Ty y ^ ")"
  | print_Ty (ForallType(tv,x)) = "ForallType(" ^ print_TyVar tv ^ "," ^ print_Ty x ^ ")"
fun print_Pat WildcardPat = "WildcardPat"
  | print_Pat (SConPat x) = "SConPat(" ^ Syntax.print_SCon x ^ ")"
  | print_Pat (VarPat(vid, ty)) = "VarPat(" ^ print_VId vid ^ "," ^ print_Ty ty ^ ")"
  | print_Pat (LayeredPat (vid, ty, pat)) = "TypedPat(" ^ print_VId vid ^ "," ^ print_Ty ty ^ "," ^ print_Pat pat ^ ")"
  | print_Pat (InstantiatedConPat(longvid, pat, tyargs)) = "InstantiatedConPat(" ^ print_LongVId longvid ^ "," ^ Syntax.print_option print_Pat pat ^ "," ^ Syntax.print_list print_Ty tyargs ^ ")"
  | print_Pat (RecordPat(x, false)) = (case Syntax.extractTuple (1, x) of
                                           NONE => "RecordPat(" ^ Syntax.print_list (Syntax.print_pair (Syntax.print_Label, print_Pat)) x ^ ",false)"
                                         | SOME ys => "TuplePat " ^ Syntax.print_list print_Pat ys
                                      )
  | print_Pat (RecordPat(x, true)) = "RecordPat(" ^ Syntax.print_list (Syntax.print_pair (Syntax.print_Label, print_Pat)) x ^ ",true)"
fun print_Exp (SConExp x) = "SConExp(" ^ Syntax.print_SCon x ^ ")"
  | print_Exp (VarExp(Syntax.MkQualified([], vid))) = "SimpleVarExp(" ^ print_VId vid ^ ")"
  | print_Exp (VarExp(x)) = "VarExp(" ^ print_LongVId x ^ ")"
  | print_Exp (RecordExp x) = (case Syntax.extractTuple (1, x) of
                                   NONE => "RecordExp " ^ Syntax.print_list (Syntax.print_pair (Syntax.print_Label, print_Exp)) x
                                 | SOME ys => "TupleExp " ^ Syntax.print_list print_Exp ys
                              )
  | print_Exp (LetExp(dec,x)) = "LetExp(" ^ print_Dec dec ^ "," ^ print_Exp x ^ ")"
  | print_Exp (AppExp(x,y)) = "AppExp(" ^ print_Exp x ^ "," ^ print_Exp y ^ ")"
  | print_Exp (HandleExp{body,exnName,handler}) = "HandleExp{body=" ^ print_Exp body ^ ",exnName=" ^ USyntax.print_VId exnName ^ ",handler=" ^ print_Exp handler ^ ")"
  | print_Exp (RaiseExp(span,x)) = "RaiseExp(" ^ print_Exp x ^ ")"
  | print_Exp (IfThenElseExp(x,y,z)) = "IfThenElseExp(" ^ print_Exp x ^ "," ^ print_Exp y ^ "," ^ print_Exp z ^ ")"
  | print_Exp (CaseExp(_,x,ty,y)) = "CaseExp(" ^ print_Exp x ^ "," ^ print_Ty ty ^ "," ^ Syntax.print_list (Syntax.print_pair (print_Pat,print_Exp)) y ^ ")"
  | print_Exp (FnExp(pname,pty,body)) = "FnExp(" ^ print_VId pname ^ "," ^ print_Ty pty ^ "," ^ print_Exp body ^ ")"
  | print_Exp (ProjectionExp { label = label, recordTy = recordTy, fieldTy = fieldTy }) = "ProjectionExp{label=" ^ Syntax.print_Label label ^ ",recordTy=" ^ print_Ty recordTy ^ ",fieldTy=" ^ print_Ty fieldTy ^ "}"
  | print_Exp (TyAbsExp(tv, exp)) = "TyAbsExp(" ^ print_TyVar tv ^ "," ^ print_Exp exp ^ ")"
  | print_Exp (TyAppExp(exp, ty)) = "TyAppExp(" ^ print_Exp exp ^ "," ^ print_Ty ty ^ ")"
  | print_Exp (RecordEqualityExp(fields)) = "RecordEqualityExp(" ^ Syntax.print_list (Syntax.print_pair (Syntax.print_Label, print_Exp)) fields ^ ")"
  | print_Exp (DataTagExp exp) = "DataTagExp(" ^ print_Exp exp ^ ")"
  | print_Exp (DataPayloadExp exp) = "DataPayloadExp(" ^ print_Exp exp ^ ")"
and print_ValBind (SimpleBind (v, ty, exp)) = "SimpleBind(" ^ print_VId v ^ "," ^ print_Ty ty ^ "," ^ print_Exp exp ^ ")"
  | print_ValBind (TupleBind (xs, exp)) = "TupleBind(" ^ Syntax.print_list (Syntax.print_pair (print_VId, print_Ty)) xs ^ "," ^ print_Exp exp ^ ")"
and print_Dec (ValDec (valbind)) = "ValDec(" ^ print_ValBind valbind ^ ")"
  | print_Dec (RecValDec (valbinds)) = "RecValDec(" ^ Syntax.print_list print_ValBind valbinds ^ ")"
  | print_Dec (DatatypeDec datbinds) = "DatatypeDec"
  | print_Dec (ExceptionDec _) = "ExceptionDec"
val print_Decs = Syntax.print_list print_Dec
end (* structure PrettyPrint *)
end (* structure FSyntax *)

structure ToFSyntax = struct
type Context = { nextVId : int ref
               }
datatype Env' = MkEnv of Env
withtype Env = { valMap : {} USyntax.VIdMap.map
               , tyConMap : FSyntax.TyCon USyntax.TyConMap.map
               , equalityForTyVarMap : USyntax.VId USyntax.TyVarMap.map
               , strMap : Env' Syntax.StrIdMap.map
               }
val emptyEnv = { valMap = USyntax.VIdMap.empty
               , tyConMap = USyntax.TyConMap.empty
               , equalityForTyVarMap = USyntax.TyVarMap.empty
               , strMap = Syntax.StrIdMap.empty
               }
fun mergeEnv(env1 : Env, env2 : Env)
    = { valMap = USyntax.VIdMap.unionWith #2 (#valMap env1, #valMap env2)
      , tyConMap = USyntax.TyConMap.unionWith #2 (#tyConMap env1, #tyConMap env2)
      , equalityForTyVarMap = USyntax.TyVarMap.unionWith #2 (#equalityForTyVarMap env1, #equalityForTyVarMap env2)
      , strMap = Syntax.StrIdMap.unionWith #2 (#strMap env1, #strMap env2)
      }

fun updateEqualityForTyVarMap(f, env : Env) = { valMap = #valMap env
                                              , tyConMap = #tyConMap env
                                              , equalityForTyVarMap = f (#equalityForTyVarMap env)
                                              , strMap = #strMap env
                                              }

fun envWithValEnv valEnv : Env = { valMap = valEnv
                                 , tyConMap = USyntax.TyConMap.empty
                                 , equalityForTyVarMap = USyntax.TyVarMap.empty
                                 , strMap = Syntax.StrIdMap.empty
                                 }

fun freshVId(ctx : Context, name: string) = let val n = !(#nextVId ctx)
                                            in #nextVId ctx := n + 1
                                             ; USyntax.MkVId(name, n)
                                            end

local structure U = USyntax
      structure F = FSyntax
      (* toFTy : Context * Env * USyntax.Ty -> FSyntax.Ty *)
      (* toFPat : Context * Env * USyntax.Pat -> unit USyntax.VIdMap.map * FSyntax.Pat *)
      (* toFExp : Context * Env * USyntax.Exp -> FSyntax.Exp *)
      (* toFDecs : Context * Env * USyntax.Dec list -> FSyntax.Dec list *)
      (* getEquality : Context * Env * USyntax.Ty -> FSyntax.Exp *)
      val overloads = let open Typing InitialEnv
                      in List.foldl (fn ((vid, xs), m) => USyntax.VIdMap.insert (m, vid, List.foldl USyntax.TyConMap.insert' USyntax.TyConMap.empty xs)) USyntax.VIdMap.empty
                                    [(VId_abs, [(primTyCon_int, VId_Int_abs)
                                               ,(primTyCon_real, VId_Real_abs)
                                               ]
                                     )
                                    ,(VId_TILDE, [(primTyCon_int, VId_Int_TILDE)
                                                 ,(primTyCon_real, VId_Real_TILDE)
                                                 ]
                                     )
                                    ,(VId_div, [(primTyCon_int, VId_Int_div)
                                               ,(primTyCon_word, VId_Word_div)
                                               ]
                                     )
                                    ,(VId_mod, [(primTyCon_int, VId_Int_mod)
                                               ,(primTyCon_word, VId_Word_mod)
                                               ]
                                     )
                                    ,(VId_TIMES, [(primTyCon_int, VId_Int_TIMES)
                                                 ,(primTyCon_word, VId_Word_TIMES)
                                                 ,(primTyCon_real, VId_Real_TIMES)
                                                 ]
                                     )
                                    ,(VId_DIVIDE, [(primTyCon_real, VId_Real_DIVIDE)
                                                  ]
                                     )
                                    ,(VId_PLUS, [(primTyCon_int, VId_Int_PLUS)
                                                ,(primTyCon_word, VId_Word_PLUS)
                                                ,(primTyCon_real, VId_Real_PLUS)
                                                ]
                                     )
                                    ,(VId_MINUS, [(primTyCon_int, VId_Int_MINUS)
                                                 ,(primTyCon_word, VId_Word_MINUS)
                                                 ,(primTyCon_real, VId_Real_MINUS)
                                                 ]
                                     )
                                    ,(VId_LT, [(primTyCon_int, VId_Int_LT)
                                              ,(primTyCon_word, VId_Word_LT)
                                              ,(primTyCon_real, VId_Real_LT)
                                              ,(primTyCon_string, VId_String_LT)
                                              ,(primTyCon_char, VId_Char_LT)
                                              ]
                                     )
                                    ,(VId_LE, [(primTyCon_int, VId_Int_LE)
                                              ,(primTyCon_word, VId_Word_LE)
                                              ,(primTyCon_real, VId_Real_LE)
                                              ,(primTyCon_string, VId_String_LE)
                                              ,(primTyCon_char, VId_Char_LE)
                                              ]
                                     )
                                    ,(VId_GT, [(primTyCon_int, VId_Int_GT)
                                              ,(primTyCon_word, VId_Word_GT)
                                              ,(primTyCon_real, VId_Real_GT)
                                              ,(primTyCon_string, VId_String_GT)
                                              ,(primTyCon_char, VId_Char_GT)
                                              ]
                                     )
                                    ,(VId_GE, [(primTyCon_int, VId_Int_GE)
                                              ,(primTyCon_word, VId_Word_GE)
                                              ,(primTyCon_real, VId_Real_GE)
                                              ,(primTyCon_string, VId_String_GE)
                                              ,(primTyCon_char, VId_Char_GE)
                                              ]
                                     )
                                    ]
                      end
in
fun toFTy(ctx : Context, env : Env, U.TyVar(span, tv)) = F.TyVar tv
  | toFTy(ctx, env, U.RecordType(span, fields)) = let fun doField(label, ty) = (label, toFTy(ctx, env, ty))
                                                  in F.RecordType (List.map doField fields)
                                                  end
  | toFTy(ctx, env, U.TyCon(span, tyargs, longtycon)) = let fun doTy ty = toFTy(ctx, env, ty)
                                                        in F.TyCon(List.map doTy tyargs, longtycon)
                                                        end
  | toFTy(ctx, env, U.FnType(span, paramTy, resultTy)) = let fun doTy ty = toFTy(ctx, env, ty)
                                                         in F.FnType(doTy paramTy, doTy resultTy)
                                                         end
and toFPat(ctx, env, U.WildcardPat span) = (USyntax.VIdMap.empty, F.WildcardPat)
  | toFPat(ctx, env, U.SConPat(span, scon)) = (USyntax.VIdMap.empty, F.SConPat(scon))
  | toFPat(ctx, env, U.VarPat(span, vid, ty)) = (USyntax.VIdMap.empty, F.VarPat(vid, toFTy(ctx, env, ty))) (* TODO *)
  | toFPat(ctx, env, U.RecordPat{sourceSpan=span, fields, wildcard}) = let fun doField(label, pat) = let val (_, pat') = toFPat(ctx, env, pat)
                                                                                                     in (label, pat')
                                                                                                     end
                                                                       in (USyntax.VIdMap.empty, F.RecordPat(List.map doField fields, wildcard)) (* TODO *)
                                                                       end
  | toFPat(ctx, env, U.ConPat(span, longvid, optpat)) = toFPat(ctx, env, U.InstantiatedConPat(span, longvid, optpat, [])) (* should not reach here *)
  | toFPat(ctx, env, U.InstantiatedConPat(span, longvid, NONE, tyargs)) = (USyntax.VIdMap.empty, F.InstantiatedConPat(longvid, NONE, List.map (fn ty => toFTy(ctx, env, ty)) tyargs))
  | toFPat(ctx, env, U.InstantiatedConPat(span, longvid, SOME payloadPat, tyargs)) = let val (m, payloadPat') = toFPat(ctx, env, payloadPat)
                                                                                     in (USyntax.VIdMap.empty, F.InstantiatedConPat(longvid, SOME payloadPat', List.map (fn ty => toFTy(ctx, env, ty)) tyargs))
                                                                                     end
  | toFPat(ctx, env, U.TypedPat(_, pat, _)) = toFPat(ctx, env, pat)
  | toFPat(ctx, env, U.LayeredPat(span, vid, ty, innerPat)) = let val (m, innerPat') = toFPat(ctx, env, innerPat)
                                                              in (USyntax.VIdMap.empty, F.LayeredPat(vid, toFTy(ctx, env, ty), innerPat')) (* TODO *)
                                                              end
and toFExp(ctx, env, U.SConExp(span, scon)) = F.SConExp(scon)
  | toFExp(ctx, env, U.VarExp(span, longvid, _)) = F.VarExp(longvid)
  | toFExp(ctx, env, U.InstantiatedVarExp(span, longvid as Syntax.MkQualified([], vid as USyntax.MkVId(vidname, _)), _, [(tyarg, cts)]))
    = if U.eqVId(vid, InitialEnv.VId_EQUAL) then
          getEquality(ctx, env, tyarg)
      else
          (case USyntax.VIdMap.find(overloads, vid) of
               SOME ov => (case tyarg of
                               U.TyCon(_, [], tycon) => (case USyntax.TyConMap.find (ov, tycon) of
                                                             SOME vid' => F.VarExp(Syntax.MkQualified([], vid'))
                                                           | NONE => raise Fail ("invalid use of " ^ vidname)
                                                        )
                             | _ => raise Fail ("invalid use of " ^ vidname)
                          )
             | NONE => if List.exists (fn USyntax.IsEqType => true | _ => false) cts then
                           F.AppExp(F.TyAppExp(F.VarExp(longvid), toFTy(ctx, env, tyarg)), getEquality(ctx, env, tyarg))
                       else
                           F.TyAppExp(F.VarExp(longvid), toFTy(ctx, env, tyarg))
          )
  | toFExp(ctx, env, U.InstantiatedVarExp(span, longvid, _, tyargs))
    = List.foldl (fn ((ty, cts), e) =>
                     if List.exists (fn USyntax.IsEqType => true | _ => false) cts then
                         F.AppExp(F.TyAppExp(e, toFTy(ctx, env, ty)), getEquality(ctx, env, ty))
                     else
                         F.TyAppExp(e, toFTy(ctx, env, ty))
                 ) (F.VarExp(longvid)) tyargs
  | toFExp(ctx, env, U.RecordExp(span, fields)) = let fun doField (label, e) = (label, toFExp(ctx, env, e))
                                                  in F.RecordExp (List.map doField fields)
                                                  end
  | toFExp(ctx, env, U.LetInExp(span, decs, e))
    = List.foldr F.LetExp (toFExp(ctx, env, e)) (toFDecs(ctx, env, decs)) (* new environment? *)
  | toFExp(ctx, env, U.AppExp(span, e1, e2)) = F.AppExp(toFExp(ctx, env, e1), toFExp(ctx, env, e2))
  | toFExp(ctx, env, U.TypedExp(span, exp, _)) = toFExp(ctx, env, exp)
  | toFExp(ctx, env, U.IfThenElseExp(span, e1, e2, e3)) = F.IfThenElseExp(toFExp(ctx, env, e1), toFExp(ctx, env, e2), toFExp(ctx, env, e3))
  | toFExp(ctx, env, U.CaseExp(span, e, ty, matches))
    = let fun doMatch(pat, exp) = let val (_, pat') = toFPat(ctx, env, pat)
                                  in (pat', toFExp(ctx, env, exp)) (* TODO: environment *)
                                  end
      in F.CaseExp(span, toFExp(ctx, env, e), toFTy(ctx, env, ty), List.map doMatch matches)
      end
  | toFExp(ctx, env, U.FnExp(span, vid, ty, body))
    = let val env' = env (* TODO *)
      in F.FnExp(vid, toFTy(ctx, env, ty), toFExp(ctx, env', body))
      end
  | toFExp(ctx, env, U.ProjectionExp { sourceSpan = span, label = label, recordTy = recordTy, fieldTy = fieldTy })
    = F.ProjectionExp { label = label, recordTy = toFTy(ctx, env, recordTy), fieldTy = toFTy(ctx, env, fieldTy) }
  | toFExp(ctx, env, U.HandleExp(span, exp, matches))
    = let val exnName = freshVId(ctx, "exn")
          val exnTy = F.TyCon([], Typing.primTyCon_exn)
          fun doMatch(pat, exp) = let val (_, pat') = toFPat(ctx, env, pat)
                                  in (pat', toFExp(ctx, env, exp)) (* TODO: environment *)
                                  end
          fun isExhaustive F.WildcardPat = true
            | isExhaustive (F.SConPat _) = false
            | isExhaustive (F.VarPat _) = true
            | isExhaustive (F.RecordPat _) = false (* exn is not a record *)
            | isExhaustive (F.InstantiatedConPat _) = false (* exn is open *)
            | isExhaustive (F.LayeredPat (_, _, pat)) = isExhaustive pat
          val matches' = List.map doMatch matches
          val matches'' = if List.exists (fn (pat, _) => isExhaustive pat) matches' then
                              matches'
                          else
                              matches' @ [(F.WildcardPat, F.RaiseExp(SourcePos.nullSpan, F.VarExp(Syntax.MkQualified([], exnName))))]
      in F.HandleExp { body = toFExp(ctx, env, exp)
                     , exnName = exnName
                     , handler = F.CaseExp(SourcePos.nullSpan, F.VarExp(Syntax.MkQualified([], exnName)), exnTy, matches'')
                     }
      end
  | toFExp(ctx, env, U.RaiseExp(span, exp)) = F.RaiseExp(span, toFExp(ctx, env, exp))
and doValBind ctx env (U.PatBind _) = raise Fail "internal error: PatBind cannot occur here"
  | doValBind ctx env (U.TupleBind (span, vars, exp)) = F.TupleBind (List.map (fn (vid,ty) => (vid, toFTy(ctx, env, ty))) vars, toFExp(ctx, env, exp))
  | doValBind ctx env (U.PolyVarBind (span, vid, U.TypeScheme(tvs, ty), exp))
    = let val ty0 = toFTy (ctx, env, ty)
          val ty' = List.foldr (fn ((tv,cts),ty1) =>
                                   case cts of
                                       [] => F.ForallType (tv, ty1)
                                     | [U.IsEqType] => F.ForallType (tv, F.FnType (F.FnType (F.PairType (F.TyVar tv, F.TyVar tv), F.TyCon([], Typing.primTyCon_bool)), ty1))
                                     | _ => raise Fail "invalid type constraint"
                               ) ty0 tvs
          fun doExp (env', [])
              = toFExp(ctx, env', exp)
            | doExp (env', (tv,cts) :: rest)
              = (case cts of
                     [] => F.TyAbsExp (tv, doExp (env', rest))
                   | [U.IsEqType] => let val vid = freshVId(ctx, "eq")
                                         val eqTy = F.FnType (F.PairType (F.TyVar tv, F.TyVar tv), F.TyCon([], Typing.primTyCon_bool))
                                         val env'' = updateEqualityForTyVarMap(fn m => USyntax.TyVarMap.insert(m, tv, vid), env')
                                     in F.TyAbsExp (tv, F.FnExp(vid, eqTy, doExp(env'', rest)))
                                     end
                   | _ => raise Fail "invalid type constraint"
                )
      in F.SimpleBind (vid, ty', doExp(env, tvs))
      end
and typeSchemeToTy(ctx, env, USyntax.TypeScheme(vars, ty))
    = let fun go env [] = toFTy(ctx, env, ty)
            | go env ((tv, []) :: xs) = let val env' = env (* TODO *)
                                        in F.ForallType(tv, go env' xs)
                                        end
            | go env ((tv, [U.IsEqType]) :: xs) = let val env' = env (* TODO *)
                                                      val eqTy = F.FnType(F.PairType(F.TyVar tv, F.TyVar tv), F.TyCon([], Typing.primTyCon_bool))
                                                  in F.ForallType(tv, F.FnType(eqTy, go env' xs))
                                                  end
            | go env ((tv, _) :: xs) = raise Fail "invalid type constraint"
      in go env vars
      end
and getEquality(ctx, env, U.TyCon(span, [], tycon))
    = let open InitialEnv
      in if U.eqUTyCon(tycon, Typing.primTyCon_int) then
             F.VarExp(Syntax.MkQualified([], VId_EQUAL_int))
         else if U.eqUTyCon(tycon, Typing.primTyCon_word) then
             F.VarExp(Syntax.MkQualified([], VId_EQUAL_word))
         else if U.eqUTyCon(tycon, Typing.primTyCon_string) then
             F.VarExp(Syntax.MkQualified([], VId_EQUAL_string))
         else if U.eqUTyCon(tycon, Typing.primTyCon_char) then
             F.VarExp(Syntax.MkQualified([], VId_EQUAL_char))
         else if U.eqUTyCon(tycon, Typing.primTyCon_bool) then
             F.VarExp(Syntax.MkQualified([], VId_EQUAL_bool))
         else if U.eqUTyCon(tycon, Typing.primTyCon_real) then
             raise Fail "'real' does not admit equality; this should have been a type error"
         else if U.eqUTyCon(tycon, Typing.primTyCon_exn) then
             raise Fail "'exn' does not admit equality; this should have been a type error"
         else
             raise Fail "equality for user-defined data types are not implemented yet"
      end
  | getEquality(ctx, env, U.TyCon(span, [tyarg], tycon))
    = if U.eqUTyCon(tycon, Typing.primTyCon_ref) then
          F.TyAppExp(F.VarExp(Syntax.MkQualified([], InitialEnv.VId_EQUAL_ref)), toFTy(ctx, env, tyarg))
      else if U.eqUTyCon(tycon, Typing.primTyCon_list) then
          F.AppExp(F.TyAppExp(F.VarExp(Syntax.MkQualified([], InitialEnv.VId_EQUAL_list)), toFTy(ctx, env, tyarg)), getEquality(ctx, env, tyarg))
      else if U.eqUTyCon(tycon, Typing.primTyCon_array) then
          F.TyAppExp(F.VarExp(Syntax.MkQualified([], InitialEnv.VId_EQUAL_array)), toFTy(ctx, env, tyarg))
      else if U.eqUTyCon(tycon, Typing.primTyCon_vector) then
          F.AppExp(F.TyAppExp(F.VarExp(Syntax.MkQualified([], InitialEnv.VId_EQUAL_vector)), toFTy(ctx, env, tyarg)), getEquality(ctx, env, tyarg))
      else
          raise Fail "equality for user-defined data types are not implemented yet"
  | getEquality (ctx, env, U.TyCon(span, tyargs, longtycon)) = raise Fail "equality for used-defined data types are not implemented yet"
  | getEquality (ctx, env, U.TyVar(span, tv)) = (case USyntax.TyVarMap.find(#equalityForTyVarMap env, tv) of
                                                     NONE => raise Fail "equality for the type variable not found"
                                                   | SOME vid => F.VarExp(Syntax.MkQualified([], vid))
                                                )
  | getEquality (ctx, env, U.RecordType(span, fields)) = let fun doField (label, ty) = (label, getEquality(ctx, env, ty))
                                                         in F.RecordEqualityExp (List.map doField fields)
                                                         end
  | getEquality (ctx, env, U.FnType _) = raise Fail "functions are not equatable; this should have been a type error"
and toFDecs(ctx, env, []) = []
  | toFDecs(ctx, env, U.ValDec(span, tvs, valbinds, valenv) :: decs)
    = List.map (fn valbind => F.ValDec (doValBind ctx env valbind)) valbinds @ toFDecs (ctx, env, decs)
  | toFDecs(ctx, env, U.RecValDec(span, tvs, valbinds, valenv) :: decs)
    = F.RecValDec (List.map (doValBind ctx env) valbinds) :: toFDecs (ctx, env, decs)
  | toFDecs(ctx, env, U.TypeDec(span, typbinds) :: decs) = toFDecs(ctx, env, decs)
  | toFDecs(ctx, env, U.DatatypeDec(span, datbinds) :: decs)
    = F.DatatypeDec (List.map (fn datbind => doDatBind(ctx, env, datbind)) datbinds) :: toFDecs(ctx, env, decs)
  | toFDecs(ctx, env, U.ExceptionDec(span, exbinds) :: decs) = List.map (fn exbind => doExBind(ctx, env, exbind)) exbinds @ toFDecs(ctx, env, decs)
and doDatBind(ctx, env, U.DatBind(span, tyvars, tycon, conbinds)) = F.DatBind(tyvars, tycon, List.map (fn conbind => doConBind(ctx, env, conbind)) conbinds)
and doConBind(ctx, env, U.ConBind(span, vid, NONE)) = F.ConBind(vid, NONE)
  | doConBind(ctx, env, U.ConBind(span, vid, SOME ty)) = F.ConBind(vid, SOME (toFTy(ctx, env, ty)))
and doExBind(ctx, env, U.ExBind(span, vid as USyntax.MkVId(name, _), optTy)) = let val tag = freshVId(ctx, name)
                                                                               in F.ExceptionDec { conName = vid
                                                                                                 , tagName = tag
                                                                                                 , payloadTy = case optTy of
                                                                                                                   NONE => NONE 
                                                                                                                 | SOME ty => SOME (toFTy(ctx, env, ty))
                                                                                                 }
                                                                               end
fun programToFDecs(ctx, env, []) = []
  | programToFDecs(ctx, env, USyntax.StrDec decs :: topdecs) = toFDecs(ctx, env, decs) @ programToFDecs(ctx, env, topdecs)
end (* local *)
end (* structure ToFSyntax *)

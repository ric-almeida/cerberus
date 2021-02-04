module IT = IndexTerms
module BT = BaseTypes
module RE = Resources
module LC = LogicalConstraints
module LS = LogicalSorts
module SymSet = Set.Make(Sym)
module StringMap = Map.Make(String)
module SymPairMap = Map.Make(SymRel.SymPair)

open Resources
open Pp

module Make (G : sig val global : Global.t end) = struct 

  module L = Local.Make(G)
  module S = Solver.Make(G)


  module VEClass = struct

    type veclass = { 
        repr : Sym.t;
        sort: LS.t;
        l_elements : SymSet.t;
        c_elements : SymSet.t;
      }

    type t = veclass


    let new_veclass l ls = { 
        repr = l;
        sort = ls;
        l_elements = SymSet.singleton l;
        c_elements = SymSet.empty;
      }

    let add_l l veclass = 
      { veclass with l_elements = SymSet.add l veclass.l_elements }

    let add_c c veclass = 
      { veclass with c_elements = SymSet.add c veclass.c_elements }

    let should_be_in_veclass local veclass (it, bt) = 
      if not (LS.equal veclass.sort (Base bt)) then false 
      else S.equal local (S (bt,veclass.repr)) it

    let classify local veclasses (l, (bt : BT.t)) : veclass list =
      let rec aux = function
        | veclass :: veclasses ->
           if should_be_in_veclass local veclass (S (bt, l), bt) 
           then (add_l l veclass :: veclasses)
           else (veclass :: aux veclasses)
        | [] -> 
           [new_veclass l (Base bt)]
      in
      aux veclasses

    let is_in_veclass veclass sym = 
      SymSet.mem sym veclass.c_elements ||
        SymSet.mem sym veclass.l_elements


    (* think about whether the 'Addr' part is always safe' *)
    let has_symbol_name veclass = 
      let all = SymSet.elements (SymSet.union veclass.c_elements veclass.l_elements) in
      Option.map (fun s -> Path.Addr s) (List.find_map Sym.name all)

    let make_name = 
      let faa counter = 
        let v = !counter in
        let () = counter := v + 1 in
        v
      in
      let sym_prefixed_int (prefix, i) = 
        "?" ^ prefix ^ string_of_int i
      in
      let unit_counter = ref 0 in
      let bool_counter = ref 0 in
      let integer_counter = ref 0 in
      let loc_counter = ref 0 in
      let array_counter = ref 0 in
      let list_counter = ref 0 in
      let tuple_counter = ref 0 in
      let struct_counter = ref 0 in
      let function_pointer_counter = ref 0 in
      let set_counter = ref 0 in
      fun veclass ->
      let (Base bt) = veclass.sort in
      sym_prefixed_int
        begin match bt with
        | Unit -> ("u", faa unit_counter)
        | Bool -> ("b", faa bool_counter)
        | Integer -> ("i", faa integer_counter)
        | Loc -> ("l", faa loc_counter)
        | Array -> ("a", faa array_counter)
        | List _ -> ("l", faa list_counter)
        | Tuple _ ->  ("t", faa tuple_counter)
        | Struct _ -> ("s", faa struct_counter)
        | FunctionPointer _ -> ("f", faa function_pointer_counter)
        | Set _ -> ("set", faa set_counter)
        end

    let compare veclass1 veclass2 = 
      Sym.compare veclass1.repr veclass2.repr

    let equal veclass1 veclass2 = 
      compare veclass1 veclass2 = 0

  end

  module VEClassSet = Set.Make(VEClass)

  module VEClassPair = struct 
    type t = VEClass.t * VEClass.t
    let compare a b = Lem_basic_classes.pairCompare VEClass.compare VEClass.compare a b
  end
  
  module VEClassRel = struct
    include Pset
    type t = VEClassPair.t Pset.set
    let empty = Pset.empty VEClassPair.compare
    let transitiveClosure = Pset.tc VEClassPair.compare
  end 


  module VEClassRelMap = Map.Make(VEClassPair)


  open VEClass

  open Path


  type naming = (Sym.t * Path.t) list

  let naming_subst subst names = 
    List.map (fun (sym,p) ->
        (Sym.subst subst sym, p)
      ) names

  let naming_substs substs names = 
    Subst.make_substs naming_subst substs names

  let pp_naming = 
    Pp.list (fun (s, p) -> parens (Sym.pp s ^^ comma ^^ Path.pp p))

  let naming_of_mapping mapping = 
    List.map (fun i ->
        Parse_ast.Mapping.(i.sym, i.path)
      ) mapping


  type variable_relation = 
    | Pointee  

  type name_kind = 
    | Given
    | Symbol
    | Derived
    | Default

  type veclass_explanation = {
      path : Path.t;
      name_kind : name_kind;
      veclass : veclass;
    }
  
  type explanation = {
      substitutions : (Sym.t, Sym.t) Subst.t list;
      veclasses : veclass_explanation list;
      relevant : SymSet.t;
    }


    
  let veclasses_partial_order local veclasses =
    List.fold_right (fun resource (graph, rels) ->
        match resource with
        | RE.Points p ->
           let found1 = 
             List.find_opt (fun veclass ->
                 should_be_in_veclass local veclass (p.pointer, BT.Loc)
               ) veclasses
           in
           let found2 = 
             List.find_opt (fun veclass ->
                 is_in_veclass veclass p.pointee
               ) veclasses
           in
           begin match found1, found2 with
           | Some veclass1, Some veclass2 
                when not (VEClassRel.mem (veclass2, veclass1) graph) ->
              (VEClassRel.add (veclass1, veclass2) graph,
               VEClassRelMap.add (veclass1, veclass2) Pointee rels)
           | _ -> 
              (graph, rels)
           end
        | _ -> 
           (graph, rels)
      ) (L.all_resources local) 
      (VEClassRel.empty, VEClassRelMap.empty)


  let veclasses_total_order local veclasses = 
    let (graph, rels) = veclasses_partial_order local veclasses in
    let graph = 
      List.fold_left (fun graph veclass1 ->
          List.fold_left (fun graph veclass2 ->
              if 
                VEClass.equal veclass1 veclass2 ||
                  VEClassRel.mem (veclass1, veclass2) graph ||
                    VEClassRel.mem (veclass2, veclass1) graph
              then
                graph
              else
                VEClassRel.transitiveClosure (VEClassRel.add (veclass1, veclass2) graph)
            ) graph veclasses
        ) graph veclasses
    in
    let graph_compare veclass1 veclass2 =
      if VEClassRel.mem (veclass1,veclass2) graph then -1 else 1
    in
    (List.sort graph_compare veclasses, rels)

  let has_given_name names veclass =
    Option.map snd
      (List.find_opt (fun (sym,name) -> is_in_veclass veclass sym) names)

  let has_derived_name (named_veclasses, rels) veclass =
    let rec aux = function
      | {veclass = named_veclass; path;_} :: named_veclasses ->
         begin match VEClassRelMap.find_opt (named_veclass, veclass) rels with
         | Some Pointee -> Some (pointee None path)
         | None -> aux named_veclasses
         end
      | [] -> None         
    in
    aux named_veclasses





  let explanation names local relevant =
    let relevant =
      List.fold_right (fun r acc -> SymSet.union acc (RE.vars_in r))
        (L.all_resources local) 
        (SymSet.union (SymSet.of_list (List.map fst names)) relevant)
    in
    let veclasses = 
      let with_logical_variables = 
        List.fold_left (fun veclasses (l, ls) ->
            if SymSet.mem l relevant then
              let (LS.Base bt) = ls in
              classify local veclasses (l, bt)
            else 
              veclasses
          ) [] (L.all_logical local)
      in
      let with_all_variables =
        List.fold_left (fun veclasses (c, (l, bt)) ->
            List.map (fun veclass ->
                if is_in_veclass veclass l || 
                     should_be_in_veclass local veclass (S (bt, l), bt)
                then add_c c veclass else veclass
              ) veclasses
          ) with_logical_variables (L.all_computational local)
      in
      let (sorted, rels) = veclasses_total_order local with_all_variables in
      let named =
        List.fold_left (fun veclasses_explanation veclass ->
            match has_given_name names veclass, 
                  has_symbol_name veclass,
                  has_derived_name (veclasses_explanation, rels) veclass with
            | Some given_name, o_symbol_name, o_derived_name ->
               let without_labels = Path.remove_labels given_name in
               let path = 
                 if Option.equal Path.equal (Some without_labels) (o_symbol_name) ||
                      Option.equal Path.equal (Some without_labels) (o_derived_name) 
                 then without_labels
                 else given_name
               in
               veclasses_explanation @ [{veclass; path; name_kind = Given}]
            | None, Some symbol_name, _ ->
               veclasses_explanation @ [{veclass; path = symbol_name; name_kind = Symbol}]
            | None, None, Some derived_name ->
               veclasses_explanation @ [{veclass; path = derived_name; name_kind = Symbol}]
            | None, None, None ->
               let name = LabeledName.{label = None; v = make_name veclass} in
               veclasses_explanation @ [{veclass; path = Var name; name_kind = Default}]
          ) [] sorted
      in
      named
    in
    let substitutions = 
      List.fold_right (fun {veclass;path;_} substs ->
          let to_substitute = SymSet.union veclass.c_elements veclass.l_elements in
          let named_symbol = Sym.fresh_named (Pp.plain (Path.pp path)) in
          SymSet.fold (fun sym substs ->
              Subst.{ before = sym; after = named_symbol } :: substs
            ) to_substitute substs 
        ) veclasses []
    in
    {substitutions; veclasses; relevant}





  let always_state = true

  let rec boring_it = 
    let open IT in
    function
    | EQ (it1, And [it2;it3]) -> IT.equal it1 it2 && IT.equal it2 it3
    | EQ (it1, it2) -> IT.equal it1 it2 || boring_it it2
    | Impl (it1, it2) -> IT.equal it1 it2 || boring_it it2
    | (And its | Or its) -> List.for_all boring_it its
    | _ -> false

  let boring_lc (LC.LC it) = boring_it it
  let interesting_lc lc = not (boring_lc lc)


  let evaluate model expr = 
    match Z3.Model.evaluate model (SolverConstraints.of_index_term G.global expr) true with
    | None -> Debug_ocaml.error "failure constructing counter model"
    | Some evaluated_expr -> Z3.Expr.to_string evaluated_expr


  let symbol_it = function
    | IT.S (_, s) -> SymSet.singleton s
    | _ -> SymSet.empty


  let pp_state_aux local {substitutions; veclasses; relevant} o_model =
    (* let resources = List.map (RE.subst_vars substitutions) (L.all_resources local) in *)
    let veclasses_with_values =
      List.map (fun veclass ->
          match o_model, veclass.veclass.sort with
          | Some model, Base Integer -> (veclass, Some (evaluate model (S (Integer, veclass.veclass.repr))))
          | _ -> (veclass, None)
        ) veclasses
    in
    let (resource_lines, reported_pointees) = 
      List.fold_right (fun resource (acc_table, acc_reported) ->
          let (entry, reported) = 
          match resource with
          | Block b ->
             let state = match b.block_type with
               | Nothing -> "block"
               | Uninit -> "uninit"
               | Padding -> "padding"
             in
             let entry =
               (Some (IT.pp (IT.subst_vars substitutions b.pointer)), 
                Some (Z.pp b.size), 
                Some !^state,
                None,
                None
               )
             in
             (entry, symbol_it b.pointer)
          | Region r ->
             let entry = 
               (Some (IT.pp (IT.subst_vars substitutions r.pointer)), 
                Some (IT.pp (IT.subst_vars substitutions r.size)), 
                Some !^"region",
                None,
                None
               )
             in
             (entry, symbol_it r.pointer)
          | Points p -> 
             (* take substs into account *)
             let found = 
               List.find_opt (fun (c,v) -> SymSet.mem p.pointee c.veclass.l_elements) 
                 veclasses_with_values 
             in
             let entry = match found with
               | Some (_, Some value) ->
                  (Some (IT.pp (IT.subst_vars substitutions p.pointer)), 
                   Some (Z.pp p.size),
                   Some !^"owned",
                   Some (Sym.pp (Sym.substs substitutions p.pointee)),
                   Some !^value
                  )
               | _ ->
                  (Some (IT.pp (IT.subst_vars substitutions p.pointer)), 
                   Some (Z.pp p.size), 
                   Some !^"owned",
                   Some (Sym.pp (Sym.substs substitutions p.pointee)), 
                   None
                  )
             in
             (entry, SymSet.union (symbol_it p.pointer) (SymSet.singleton p.pointee))
          | Predicate p ->
             let entry =
               (None, 
                None, 
                Some (pp_predicate p),
                None,
                None
               )
             in
             (entry, SymSet.empty)
          in
          (entry :: acc_table, SymSet.union reported acc_reported)
        ) (L.all_resources local) ([], SymSet.empty)
    in
    let var_lines = 
      List.filter_map (fun (c,value) ->
          let (Base bt) = c.veclass.sort in
          let relevant = not (SymSet.is_empty (SymSet.inter c.veclass.l_elements relevant)) in
          let reported = not (SymSet.is_empty (SymSet.inter c.veclass.l_elements reported_pointees)) in
          let value_pp = Option.map Pp.string value in
          if (not reported) && relevant then
            match bt with
            | BT.Loc -> 
               Some (Some (Path.pp c.path), 
                     None, 
                     None, 
                     None, 
                     value_pp)
            | _ -> 
               Some (None, 
                     None, 
                     None, 
                     Some (Path.pp c.path), 
                     value_pp)
          else
            None)
        veclasses_with_values
    in
    resource_lines @ var_lines



  let pp_state_with_model local explanation o_model =
    let lines = 
      List.map (fun (a,b,c,d,e) -> ((L,a), (L,b), (L,c), (L,d), (L,e)))
        (pp_state_aux local explanation o_model)
    in
    table5 ("location", "size", "state", "variable", "value") lines
      

  let pp_state local explanation =
    let lines = 
      List.map (fun (a,b,c,d,_) -> ((L,a), (L,b), (L,c), (L,d)))
        (pp_state_aux local explanation None)
    in
    table4 ("location", "size", "state", "variable") lines


  let json_state names local : Yojson.Safe.t = 
    let explanation = explanation names local SymSet.empty in
    let lines = 
      List.map (fun (a,b,c,d,_) : Yojson.Safe.t ->
          let jsonf doc = `String (Pp.plain doc) in
          `Assoc [("location", Option.json jsonf a);
                  ("size", Option.json jsonf b);
                  ("state", Option.json jsonf c);
                  ("variable", Option.json jsonf d)]
        ) (pp_state_aux local explanation None)
    in
    `List lines


  let state names local = 
    let explanation = explanation names local SymSet.empty in
    pp_state local explanation

  let undefined_behaviour names local o_model = 
    let explanation = explanation names local SymSet.empty in
    pp_state_with_model local explanation o_model

  let missing_ownership names local it = 
    let explanation = explanation names local (IT.vars_in it) in
    let it_pp = IT.pp (IT.subst_vars explanation.substitutions it) in
    (it_pp, pp_state local explanation)

  let unsatisfied_constraint names local lc o_model = 
    let explanation = explanation names local (LC.vars_in lc) in
    let lc_pp = LC.pp (LC.subst_vars explanation.substitutions lc) in
    (lc_pp, pp_state_with_model local explanation o_model)

  let resource names local re = 
    let explanation = explanation names local (RE.vars_in re) in
    let re_pp = RE.pp (RE.subst_vars explanation.substitutions re) in
    (re_pp, pp_state local explanation)

  let resources names local (re1, re2) = 
    let relevant = (SymSet.union (RE.vars_in re1) (RE.vars_in re2)) in
    let explanation = explanation names local relevant in
    let re1 = RE.pp (RE.subst_vars explanation.substitutions re1) in
    let re2 = RE.pp (RE.subst_vars explanation.substitutions re2) in
    ((re1, re2), pp_state local explanation)
    



end
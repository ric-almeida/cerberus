

enum {
  NUM_NODES = 16,
  LEN_LIMIT = 1 << 16,
};

struct node;

typedef struct node * tree;

struct node {
  int v;
  tree nodes[NUM_NODES];
};

/*@
function (i32) num_nodes ()
@*/

int cn_get_num_nodes (void)
/*@ cn_function num_nodes; @*/
{
  return NUM_NODES;
}

/*@
datatype tree {
  Empty_Tree {},
  Node {i32 v, list <datatype tree> children}
}

function (map <i32, datatype tree>) default_children ()

predicate {datatype tree t, i32 v, map <i32, datatype tree> children}
  Tree (pointer p)
{
  if (is_null(p)) {
    return {t: Empty_Tree {}, v: 0i32, children: default_children ()};
  }
  else {
    take V = Owned<int>(member_shift<node>(p,v));
    let nodes_ptr = member_shift<node>(p,nodes);
    take Ns = each (i32 i; (0i32 <= i) && (i < (num_nodes ())))
      {Indirect_Tree(array_shift<tree>(nodes_ptr, i))};
    let ts = array_to_list (Ns, 0i32, num_nodes ());
    return {t: Node {v: V, children: ts}, v: V, children: Ns};
  }
}

predicate (datatype tree) Indirect_Tree (pointer p) {
  take V = Owned<tree>(p);
  assert (is_null(V) || ((u64) V != 0u64));
  take T = Tree(V);
  return T.t;
}

type_synonym arc_in_array = {map <i32, i32> arr, i32 i, i32 len}

function (boolean) in_tree (datatype tree t, arc_in_array arc)
function (i32) tree_v (datatype tree t, arc_in_array arc)

function [coq_unfold] (i32) tree_v_step (datatype tree t, arc_in_array arc)
{
  match t {
    Empty_Tree {} => {
      0i32
    }
    Node {v: v, children: children} => {
      let arc2 = {arr: arc.arr, i: arc.i + 1i32, len: arc.len};
      ((arc.i < arc.len) ?
        (tree_v(nth_list((arc.arr)[arc.i], children, Empty_Tree {}), arc2)) :
        v)
    }
  }
}

function [coq_unfold] (boolean) in_tree_step (datatype tree t, arc_in_array arc)
{
  match t {
    Empty_Tree {} => {
      false
    }
    Node {v: v, children: children} => {
      let arc2 = {arr: arc.arr, i: arc.i + 1i32, len: arc.len};
      ((arc.i < arc.len) ?
        (in_tree(nth_list((arc.arr)[arc.i], children, Empty_Tree {}), arc2)) :
        true)
    }
  }
}

lemma in_tree_tree_v_lemma (datatype tree t, arc_in_array arc,
    map <i32, datatype tree> t_children)
  requires
    0i32 <= arc.i;
    arc.len <= LEN_LIMIT;
  ensures
    (tree_v(t, arc)) == (tree_v_step(t, arc));
    (in_tree(t, arc)) == (in_tree_step(t, arc));
@*/

int
lookup_rec (tree t, int *path, int i, int path_len, int *v)
/*@ requires is_null(t) || ((u64) t != 0u64); @*/
/*@ requires path_len <= LEN_LIMIT; @*/
/*@ requires take T = Tree(t); @*/
/*@ requires take Xs = each (i32 j; (0i32 <= j) && (j < path_len))
    {Owned(array_shift(path, j))}; @*/
/*@ requires ((0i32 <= path_len) && (0i32 <= i) && (i <= path_len)); @*/
/*@ requires each (i32 j; (0i32 <= j) && (j < path_len))
    {(0i32 <= (Xs[j])) && ((Xs[j]) < (num_nodes ()))}; @*/
/*@ requires take V = Owned(v); @*/
/*@ requires let arc = {arr: Xs, i: i, len: path_len}; @*/
/*@ ensures take T2 = Tree(t); @*/
/*@ ensures T2.t == {T.t}@start; @*/
/*@ ensures T2.children == {T.children}@start; @*/
/*@ ensures take Xs2 = each (i32 j; (0i32 <= j) && (j < path_len))
    {Owned(array_shift(path, j))}; @*/
/*@ ensures Xs2 == {Xs}@start; @*/
/*@ ensures take V2 = Owned(v); @*/
/*@ ensures ((return == 0i32) && (not (in_tree (T2.t, arc))))
  || ((return == 1i32) && (in_tree (T2.t, arc)) && ((tree_v (T2.t, arc)) == V2)); @*/
{
  int idx = 0;
  int r = 0;
  if (! t) {
    /*@ apply in_tree_tree_v_lemma(T.t, arc, T.children); @*/
    return 0;
  }
  if (i >= path_len) {
    *v = t->v;
    /*@ apply in_tree_tree_v_lemma(T.t, arc, T.children); @*/
    return 1;
  }
  /*@ instantiate i; @*/
  /*@ extract Owned<int>, i; @*/
  idx = path[i];
  /*@ extract Indirect_Tree, idx; @*/
  r = lookup_rec(t->nodes[idx], path, i + 1, path_len, v);
  /*@ apply in_tree_tree_v_lemma(T.t, arc, T.children); @*/
  if (r)
    return 1;
  else
    return 0;
}

#ifdef NOT_CURRENTLY_WORKING
int
lookup (tree t, int *path, int path_len, int *v)
/*@ requires let T = Tree(t); @*/
/*@ requires let A = Arc(path, 0, path_len); @*/
/*@ requires let V = Owned(v); @*/
/*@ ensures let T2 = Tree(t); @*/
/*@ ensures T2.t == {T.t}@start; @*/
/*@ ensures let A2 = Arc(path, 0, path_len); @*/
/*@ ensures A2.arc == {A.arc}@start; @*/
/*@ ensures let V2 = Owned(v); @*/
/*@ ensures ((return == 0) && ((T2.t[A2.arc]) == Node_None {}))
  || ((return == 1) && ((T2.t[A2.arc]) == Node {v: V2})); @*/
{
  int i;

  for (i = 0; i < path_len; i ++)
  {
    if (! t) {
      return 0;
    }
    t = t->nodes[path[i]];
  }
  if (! t) {
    return 0;
  }
  *v = t->v;
  return 1;
}
#endif


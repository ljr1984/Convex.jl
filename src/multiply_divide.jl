#############################################################################
# multiply_divide.jl
# Handles scalar multiplication, maatrix multiplication, and scalar division
# of variables, constants and expressions.
# All expressions and atoms are subtpyes of AbstractExpr.
# Please read expressions.jl first.
#############################################################################

export *
export sign, monotonicity, curvature, evaluate, conic_form

### Scalar and matrix multiplication

type MultiplyAtom <: AbstractExpr
  head::Symbol
  children_hash::Uint64
  children::(AbstractExpr, AbstractExpr)
  size::(Int64, Int64)

  function MultiplyAtom(x::AbstractExpr, y::AbstractExpr)
    if x.size == (1, 1)
      sz = y.size
    elseif y.size == (1, 1)
      sz = x.size
    elseif x.size[2] ==  y.size[1]
      sz = (x.size[1], y.size[2])
    else
      error("Cannot multiply two expressions of sizes $(x.size) and $(y.size)")
    end
    children = (x, y)
    return new(:*, hash(children), children, sz)
  end
end

function sign(x::MultiplyAtom)
  return sign(x.children[1]) * sign(x.children[2])
end

function monotonicity(x::MultiplyAtom)
  return (sign(x.children[2]) * Nondecreasing(), sign(x.children[1]) * Nondecreasing())
end

# Multiplication has an indefinite hessian, so if neither children are constants,
# the curvature of the atom will violate DCP.
function curvature(x::MultiplyAtom)
  if vexity(x.children[1]) != ConstVexity() && vexity(x.children[2]) != ConstVexity()
    return NotDCP()
  else
    return ConstVexity()
  end
end

function evaluate(x::MultiplyAtom)
  return evaluate(x.children[1]) * evaluate(x.children[2])
end

function conic_form(x::MultiplyAtom, unique_constr)
  if !((x.head, x.children_hash) in unique_constr)
    # scalar multiplication
    if x.children[1].size == (1, 1) || x.children[2].size == (1, 1)
      if x.children[1].head == :constant
        const_child = x.children[1]
        expr_child = x.children[2]
      else
        const_child = x.children[2]
        expr_child = x.children[1]
      end
      objective, constraints = conic_form(expr_child, unique_constr)

      # make sure all 1x1 sized objects are interpreted as scalars, since
      # [1] * [1, 2, 3] is illegal in julia, but 1 * [1, 2, 3] is ok
      if const_child.size == (1, 1)
        const_multiplier = const_child.value[1]
      else
        const_multiplier = reshape(const_child.value, get_vectorized_size(const_child), 1)
      end

      objective = const_multiplier * objective

    # left matrix multiplication
    elseif x.children[1].head == :constant
      objective, constraints = conic_form(x.children[2], unique_constr)
      objective = kron(speye(x.size[2]), x.children[1].value) * objective
    # right matrix multiplication
    else
      objective, constraints = conic_form(x.children[1], unique_constr)
      objective = kron(x.children[2].value', speye(x.size[1])) * objective
    end
    unique_constr[(x.head, x.children_hash)] = (objective, constraints)
  end
  return unique_constr[(x.head, x.children_hash)]
end

*(x::AbstractExpr, y::AbstractExpr) = MultiplyAtom(x, y)
*(x::Value, y::AbstractExpr) = MultiplyAtom(Constant(x), y)
*(x::AbstractExpr, y::Value) = MultiplyAtom(x, Constant(y))

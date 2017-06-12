

"""
    fermidirac

Return the Fermi-Dirac distribution function for the given temperature.
For energy whose absolute value is less than `etol`, return 0.5.
"""
function fermidirac{T <:AbstractFloat}(temperature ::T;
                                       ttol::T=eps(T),
                                       etol::T=sqrt(eps(T)))
  @assert(temperature >= 0)
  @assert(ttol >= 0)
  @assert(etol >= 0)
  if temperature < ttol
    function(e ::T)
      if e <= -etol
        return T(1.0)
      elseif e < etol
        return T(0.5)
      else
        return T(0.0)
      end
    end
  else
    beta = 1.0 / temperature
    function(e ::T)
      return T(1.0 / (exp(beta * e) + 1.0))
    end
  end
end


"""
    fermidirac

Return the Fermi-Dirac distribution function for the given temperature.
For energy whose absolute value is less than `etol`, return 0.5.
"""
function fermidirac{T <:Integer}(temperature ::T;
                                 ttol::Float64=eps(Float64),
                                 etol::Float64=sqrt(eps(Float64)))
  @assert(temperature >= 0, "temperature should be non-negative")
  @assert(ttol >= 0, "ttol should be non-negative")
  @assert(etol >= 0, "etol should be non-negative")
  if temperature == 0
    function(e ::Float64)
      if e <= -etol
        return 1.0
      elseif e < etol
        return 0.5
      else
        return 0.0
      end
    end
  else
    beta = 1.0 / Float64(temperature)
    function(e ::Float64)
      return 1.0 / (exp(beta * e) + 1.0)
    end
  end
end


const CollectRow = Tuple{Int64, Int64, Vector{Float64}}
const DeployRow = Tuple{Int64, Int64, Vector{Float64}, Vector{Tuple{Int64, Complex128, Bool}}}

type HFBComputer
  unitcell ::UnitCell
  hoppings ::Vector{Embed.Hopping}
  temperature ::Float64
  fermi ::Function
  ρ_registry ::Vector{CollectRow}
  t_registry ::Vector{CollectRow}
  Γ_registry ::Vector{DeployRow}
  Δ_registry ::Vector{DeployRow}
end


function HFBComputer(ham::HFBHamiltonian,
                    temperature::Real;
                    ttol=eps(Float64),
                    etol=sqrt(eps(Float64)))
  @assert(ttol >= 0.0, "ttol should be non-negative")
  @assert(etol >= 0.0, "etol should be non-negative")
  @assert(temperature >= 0, "temperature should be non-negative")
  dim = dimension(ham.unitcell)

  unitcell = ham.unitcell
  hoppings = [Embed.embed(unitcell, hop) for hop in ham.hoppings]
  fermi = fermidirac(temperature)

  function getdistance(i ::Int64, j ::Int64, Rij::AbstractVector{Int64})
    ri, rj = getorbitalcoord(unitcell, i), getorbitalcoord(unitcell, j)
    rj = rj + Rij
    ri, rj = fract2carte(unitcell, ri), fract2carte(unitcell, rj)
    return rj - ri
  end

  collect_reg = Dict()
  deploy_reg = Dict()

  # always collect density
  for (i, orb) in enumerate(ham.unitcell.orbitals)
    R = zeros(Int64, dimension(ham.unitcell))
    r = zeros(Float64, dimension(ham.unitcell))
    collect_reg[i, i, R] = (length(collect_reg)+1, (i, i, r))
  end

  for hopmf in ham.particle_hole_interactions
    let
      (k,l,Rkl) = hopmf.source
      rkl = getdistance(k, l, Rkl)
      collect_reg[k,l,Rkl] = (length(collect_reg)+1, (k, l, rkl))
    end

    let
      v = hopmf.amplitude
      (i,j,Rij) = hopmf.target
      rij = getdistance(i, j, Rij)
      deploy_reg[i,j,Rij] = (length(deploy_reg)+1, (i, j, rij, []))
    end
  end

  for hopmf in ham.particle_hole_interactions
    v = hopmf.amplitude
    (i,j,Rij) = hopmf.target
    (k,l,Rkl) = hopmf.source
    srcidx = collect_reg[k,l,Rkl][1]
    star = hopmf.targetconj
    push!( deploy_reg[i,j,Rij][2][4], (srcidx, v, star) )
  end

  ρ_registry = sort([(idx, val) for (key, (idx, val)) in collect_reg], by=(x) -> x[1])
  Γ_registry = sort([(idx, val) for (key, (idx, val)) in deploy_reg], by=(x) -> x[1])
  ρ_registry = [val for (idx, val) in ρ_registry]
  Γ_registry = [val for (idx, val) in Γ_registry]

  collect_reg = Dict()
  deploy_reg = Dict()

  for hopmf in ham.particle_particle_interactions
    let
      (k,l,Rkl) = hopmf.source
      rkl = getdistance(k, l, Rkl)
      collect_reg[k,l,Rkl] = (length(collect_reg)+1, (k, l, rkl))
    end

    let
      v = hopmf.amplitude
      (i,j,Rij) = hopmf.target
      rij = getdistance(i, j, Rij)
      deploy_reg[i,j,Rij] = (length(deploy_reg)+1, (i, j, rij, []))
    end
  end

  for hopmf in ham.particle_particle_interactions
    v = hopmf.amplitude
    (i,j,Rij) = hopmf.target
    (k,l,Rkl) = hopmf.source
    srcidx = collect_reg[(k,l,Rkl)][1]
    neg = hopmf.negate
    push!( deploy_reg[i,j,Rij][2][4], (srcidx, v, neg) )
  end
  t_registry = sort([(idx, val) for (key, (idx, val)) in collect_reg], by=(x) -> x[1])
  Δ_registry = sort([(idx, val) for (key, (idx, val)) in deploy_reg], by=(x) -> x[1])
  t_registry = [val for (idx, val) in t_registry]
  Δ_registry = [val for (idx, val) in Δ_registry]

  return HFBComputer(unitcell,
                     hoppings,
                     temperature, fermi,
                     ρ_registry, t_registry,
                     Γ_registry, Δ_registry)
end


"""
func : (idx, i, j, r) -> val
"""
function makesourcefields(funcρ ::Function, funct ::Function, computer ::HFBComputer)
  ρs = zeros(Complex128, length(computer.ρ_registry))
  ts = zeros(Complex128, length(computer.t_registry))

  for (idx, (i, j, r)) in enumerate(computer.ρ_registry)
    v = funcρ(idx, i, j, r)
    if i==j && all((x)->x==0, r)
      ρs[idx] = real(v)
    else
      ρs[idx] = v
    end
  end
  for (idx, (i, j, r)) in enumerate(computer.t_registry)
    ts[idx] = funct(idx, i, j, r)
  end
  return (ρs, ts)
end


function makesourcefields(computer ::HFBComputer)
  ρs = zeros(Complex128, length(computer.ρ_registry))
  ts = zeros(Complex128, length(computer.t_registry))
  return (ρs, ts)
end


function computetargetfields(computer ::HFBComputer,
                          ρs ::AbstractVector{Complex128},
                          ts ::AbstractVector{Complex128})
  Γs = zeros(Complex128, length(computer.Γ_registry))
  Δs = zeros(Complex128, length(computer.Δ_registry))
  for (tgtidx, (i, j, r, srcs)) in enumerate(computer.Γ_registry)
    value = 0.0 + 0.00im
    for (srcidx, amplitude, star) in srcs
      value += amplitude * (star ? conj(ρs[srcidx]) : ρs[srcidx])
    end
    Γs[tgtidx] = value
  end

  for (tgtidx, (i, j, r, srcs)) in enumerate(computer.Δ_registry)
    value = 0.0 + 0.00im
    for (srcidx, amplitude, neg) in srcs
      value += amplitude * (neg ? -ts[srcidx] : ts[srcidx])
    end
    Δs[tgtidx] = value
  end
  return (Γs, Δs)
end


"""
"""
function makehamiltonian(computer ::HFBComputer,
                         Γs ::AbstractVector{Complex128},
                         Δs ::AbstractVector{Complex128})
  norb = numorbital(computer.unitcell)
  hk = Generator.generatefast(computer.unitcell, computer.hoppings)
  function(k ::AbstractVector{Float64})
    out = zeros(Complex128, (norb, 2, norb, 2))
    # 1/3. non-interacting kinetic part
    hk( k, view(out, :,1,:,1))
    hk(-k, view(out, :,2,:,2))
    # 2/3. Gamma
    for (idx, Γ) in enumerate(Γs)
      (i, j, r, s) = computer.Γ_registry[idx]
      out[i,1,j,1] += Γ * exp(1im * dot( k, r))
      out[i,2,j,2] += Γ * exp(1im * dot(-k, r))
    end

    out[:,2,:,2] = -transpose(out[:,2,:,2])

    # 3/3. Delta
    for (idx, Δ) in enumerate(Δs)
      (i, j, r, s) = computer.Δ_registry[idx]
      out[i,1,j,2] += Δ * exp(1im * dot( k, r))
      out[j,2,i,1] += conj(Δ) * exp(-1im * dot(k, r))
    end
    return reshape(out, (norb*2, norb*2))
  end
end

"""
    makegreencollectors

Returns a function which has the following signature
```
collector(k, eigenvalues, eigenvectors, ρout, tout)
```
"""
function makegreencollectors(computer::HFBComputer)
  fermi = computer.fermi
  norb = numorbital(computer.unitcell)
  ρ_registry = computer.ρ_registry
  t_registry = computer.t_registry

  function(k::AbstractVector{Float64},
           eigenvalues ::AbstractVector{Float64},
           eigenvectors ::AbstractMatrix{Complex128},
           ρout ::AbstractVector{Complex128},
           tout ::AbstractVector{Complex128})
    @assert(length(eigenvalues) == 2*norb)
    @assert(size(eigenvectors) == (2*norb, 2*norb))

    f = [fermi(e) for e in eigenvalues]
    ψ = reshape(eigenvectors, (norb, 2, norb*2))
    u = ψ[:, 1, :]
    v = ψ[:, 2, :]

    function ρfunc(i ::Int64, j ::Int64)
      sum(f .* u[i, :] .* conj(u[j, :]))
    end
    function tfunc(i ::Int64, j ::Int64)
      sum(f .* u[i, :] .* conj(v[j, :]))
    end

    for (idx, (i, j, r)) in enumerate(ρ_registry)
      ρout[idx] += ρfunc(i, j) * exp(-1im * dot(k, r))
    end
    for (idx, (i, j, r)) in enumerate(t_registry)
      tout[idx] += tfunc(i, j) * exp(-1im * dot(k, r))
    end
  end
end
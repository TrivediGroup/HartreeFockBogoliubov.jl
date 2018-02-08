@testset "FractCoord" begin
  @testset "Explicit Construction" begin
    fractcoord = FractCoord([-2, 1], [0.8, 0.5])
    @test fractcoord.whole == [-2, 1]
    @test fractcoord.fraction == [0.8, 0.5]
  end

  @testset "Construction by Raw" begin
    fractcoord = FractCoord([-1.2, 1.5])
    @test fractcoord.whole == [-2, 1]
    @test isapprox(fractcoord.fraction, [0.8, 0.5])
  end

  @testset "Zero Construction" begin
    fractcoord = FractCoord(2)
    @test fractcoord.whole == [0,0]
    @test fractcoord.fraction == [0.0, 0.0]
  end

  @testset "methods" begin
    fractcoord = FractCoord([-2, 1], [0.8, 0.5])
    @test dimension(fractcoord) == 2
  end

  @testset "failures" begin
    @test_throws AssertionError FractCoord([-1, 1], [1.0, 2.0])
  end

  @testset "isapprox" begin
    fractcoord1 = FractCoord([-2, 1], [0.8, 0.5])
    fractcoord2 = FractCoord([-2, 1], [0.8, 0.5 + 1E-10])
    fractcoord3 = FractCoord([-1, 1], [0.8, 0.5])
    fractcoord4 = FractCoord([-1, 1], [0.8, 0.5+1E-2])

    @test isapprox(fractcoord1, fractcoord2)
    @test !isapprox(fractcoord1, fractcoord3)
    @test !isapprox(fractcoord1, fractcoord4)
  end

  @testset "Operators" begin
    lvs = [0.5 0.0; 0.0 1.0]
    fc1 = FractCoord([-2, 1], [0.8, 0.5])
    fc2 = FractCoord([1, 2], [0.1, 0.8])
    w = [3, 1]
    @test isapprox(fc1 + fc2, FractCoord([-1, 4], [0.9, 0.3]))
    @test isapprox(fc1 - fc2, FractCoord([-3, -2], [0.7, 0.7]))
    @test isapprox(fc1 + w, FractCoord([1, 2], [0.8, 0.5]))
    @test isapprox(fc1 - w, FractCoord([-5, 0], [0.8, 0.5]))
  end

  @testset "Conversion fract2carte/carte2fract" begin
    latticevectors = [0.5 0.0; 0.0 1.0]
    rawfractcoord = [-1.2, 1.5]

    correctfractcoord = FractCoord([-2, 1], [0.8, 0.5])
    correctcartecoord = [-0.6, 1.5]

    fractcoord = FractCoord(rawfractcoord)
    cartecoord = fract2carte(latticevectors, fractcoord)
    newfractcoord = carte2fract(latticevectors, cartecoord)
    @test isapprox(fractcoord, correctfractcoord)
    @test isapprox(cartecoord, correctcartecoord)
    @test isapprox(newfractcoord, correctfractcoord)
  end

  #=
  @testset "Honeycomb" begin
    a1 = [ sqrt(3.0) * 0.5, 0.5]
    a2 = [-sqrt(3.0) * 0.5, 0.5]
    a3 = [0.0, -1.0]
    b1 = a1 - a2
    b2 = a2 - a3
    b3 = a3 - a1
    lvs = [b1 b2]

    @show a1
    @show a2
    @show a3

    @show carte2fract(lvs, a1)
    @show carte2fract(lvs, a2)
    @show carte2fract(lvs, a3)

    fa1 = carte2fract(lvs, a1)
    fa2 = carte2fract(lvs, a2)
    fa3 = carte2fract(lvs, a3)

    @show fract2carte(lvs, fa1)
    @show fract2carte(lvs, fa2)
    @show fract2carte(lvs, fa3)
  end
  =#
end
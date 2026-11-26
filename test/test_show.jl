@testset "show" begin
    function plain(t; size = (24, 80), limit = true, kw...)
        b = IOBuffer()
        show(IOContext(b, :displaysize => size, :limit => limit, kw...),
            MIME"text/plain"(), t)
        String(take!(b))
    end
    lines(xs...) = join(xs, "\n")

    t = Table(; store = ["A", "A", "B"], date = [1, 2, 1],
                revenue = [10.0, missing, 5.0])
    before = copy(t)
    @test plain(t) == lines(
        "3×3 Table",
        " store    date   revenue",
        " String  Int64  Float64?",
        " " * "─"^23,
        " A           1      10.0",
        " A           2   missing",
        " B           1       5.0")
    @test isequal(t, before)
    @test sprint(show, t) == "3×3 Table"
    @test plain(Table()) == "0×0 Table"
    @test plain(Table(; a = Int[])) ==
        lines("0×1 Table", "     a", " Int64", " ─────")
    @test !endswith(plain(t), "\n")
    @test all(l -> l == rstrip(l), split(plain(t), "\n"))

    # Long table: widths 5, 6; budget 3 is 2 rows, ⋮, 1 row.
    long = Table(; a = collect(1:20), s = ["r$i" for i in 1:20])
    @test plain(long; size = (10, 80)) == lines(
        "20×2 Table",
        "     a  s",
        " Int64  String",
        " " * "─"^13,
        "     1  r1",
        "     2  r2",
        "     ⋮  ⋮",
        "    20  r20")
    # Budget never drops below 2: one row, ⋮, one row.
    @test plain(long; size = (5, 80)) == lines(
        "20×2 Table",
        "     a  s",
        " Int64  String",
        " " * "─"^13,
        "     1  r1",
        "     ⋮  ⋮",
        "    20  r20")
    # A table that fits the budget shows every row (3 of 3).
    @test plain(Table(; a = [1, 2, 3]); size = (10, 80)) == lines(
        "3×1 Table", "     a", " Int64", " " * "─"^5,
        "     1", "     2", "     3")

    # Wide table: k columns take 7k - 1 <= 40, so 5 fit.
    wide = Table(; (Symbol("c", i) => [i] for i in 1:30)...)
    @test plain(wide; size = (24, 40)) == lines(
        "1×30 Table",
        "    c1     c2     c3     c4     c5",
        " Int64  Int64  Int64  Int64  Int64",
        " " * "─"^33,
        "     1      2      3      4      5",
        "… and 25 more columns: c6, c7, c8, c9, …")
    @test textwidth(split(plain(wide; size = (24, 40)), "\n")[end]) == 40
    # Singular wording; a list that fits is not cut (22 of 25).
    @test plain(Table(; abcdefghijkl = [1], b = ["abcdefghijklmnop"]); size = (24, 25)) ==
        lines("1×2 Table", " abcdefghijkl", " " * " "^7 * "Int64", " " * "─"^12,
            " " * " "^11 * "1", "… and 1 more column: b")
    # The first column always shows; the last line is cut to 4.
    @test plain(Table(; abcdefgh = [1], z = [2]); size = (24, 4)) == lines(
        "1×2 Table", " abcdefgh", " " * " "^3 * "Int64", " " * "─"^8,
        " " * " "^7 * "1", "… a…")

    # Unicode and space names align by textwidth (名前 is 4).
    @test plain(Table(; var"unit price" = [1], 名前 = ["x"])) == lines(
        "1×2 Table",
        " unit price  名前",
        "      Int64  String",
        " " * "─"^18,
        " " * " "^9 * "1  x")

    # Names, types, cells are cut to 20: 19 columns and "…".
    s30 = "abcdefghijklmnopqrstuvwxyz0123"
    @test plain(Table(; s = [s30])) == lines(
        "1×1 Table", " s", " String", " " * "─"^20, " abcdefghijklmnopqrs…")
    @test plain(Table(; abcdefghijklmnopqrstuvwxy = [1])) == lines(
        "1×1 Table", " abcdefghijklmnopqrs…", " " * " "^15 * "Int64", " " * "─"^20,
        " " * " "^19 * "1")
    @test plain(Table(; d = [Dict(:a => [1])])) == lines(
        "1×1 Table", " d", " Dict{Symbol, Vector…", " " * "─"^20, " Dict(:a=>[1])")
    # CJK stays whole: 9 characters take 18 columns, then "…".
    @test plain(Table(; s = ["名"^15])) == lines(
        "1×1 Table", " s", " String", " " * "─"^19, " " * "名"^9 * "…")

    # Control characters are escaped; backslashes, quotes stay.
    @test plain(Table(; s = ["a\nb", "\e[1m\x01"])) == lines(
        "2×1 Table", " s", " String", " " * "─"^9, " a\\nb", " \\e[1m\\x01")
    @test plain(Table(; s = ["a\\b\"c"])) == lines(
        "1×1 Table", " s", " String", " " * "─"^6, " a\\b\"c")
    @test plain(Table(; c = ['\t'])) == lines(
        "1×1 Table", " c", " Char", " " * "─"^4, " \\t")

    # Non-printable characters are escaped, U+202E (bidi) too.
    @test plain(Table(; s = ["a\u202eb"])) == lines(
        "1×1 Table", " s", " String", " " * "─"^8, " a\\u202eb")
    @test plain(Table(; var"a\u202eb" = [1])) == lines(
        "1×1 Table", " a\\u202eb", " " * " "^3 * "Int64", " " * "─"^8,
        " " * " "^7 * "1")
    # Ordinary text stays raw: accents, CJK, emoji, spaces.
    @test plain(Table(; s = ["é名😀"])) == lines(
        "1×1 Table", " s", " String", " " * "─"^6, " é名😀")
    @test all(isprint, "é名😀 \u0301\u00a0\u3000")

    # Strings print unquoted; String "missing" is not missing.
    @test plain(Table(; s = ["missing", "x"])) == lines(
        "2×1 Table", " s", " String", " " * "─"^7, " missing", " x")
    # Bool is Real, so it is right-aligned.
    @test plain(Table(; b = [true, false])) == lines(
        "2×1 Table", "     b", "  Bool", " " * "─"^5, "  true", " false")
    # An all-missing column is labelled Missing, left-aligned.
    @test plain(Table(; m = [missing, missing])) == lines(
        "2×1 Table", " m", " Missing", " " * "─"^7, " missing", " missing")
    # Union{Missing,String} is left-aligned, labelled String?.
    @test plain(Table(; s = ["a", missing])) == lines(
        "2×1 Table", " s", " String?", " " * "─"^7, " a", " missing")
    # Mixed-type column (Any) is left-aligned, labelled Any.
    @test plain(Table(; x = Any[1, "a"])) == lines(
        "2×1 Table", " x", " Any", " " * "─"^3, " 1", " a")
    # A nested Table shows its compact form.
    @test plain(Table(; t = [Table(; a = [1])])) == lines(
        "1×1 Table", " t", " Table", " " * "─"^9, " 1×1 Table")

    # Colour: only missing is grey; padding ignores the codes.
    m = Table(; a = [1, missing])
    grey = "\e[90mmissing\e[39m"
    @test plain(m; color = true) == lines(
        "2×1 Table", "       a", "  Int64?", " " * "─"^7, "       1", " " * grey)
    @test plain(m) == lines(
        "2×1 Table", "       a", "  Int64?", " " * "─"^7, "       1", " missing")
    @test !occursin("\e", plain(m))
    @test !occursin("\e[", plain(Table(; s = ["missing"]); color = true))
    # No trailing spaces: a row of "" is an empty line.
    @test plain(Table(; s = ["", "ab"])) == lines(
        "2×1 Table", " s", " String", " " * "─"^6, "", " ab")

    # The per-column inner functions are type-stable.
    @inferred TableOps._cells([1, missing], [1, 0, 2])
    @inferred TableOps._glimpse_values(["a", "b"], 10)
    @test TableOps._glimpse_values(["a", missing, "c"], 5) ==
        (["a"], [false], ", …")
    @test TableOps._cells([1, missing], [1, 0, 2]) ==
        (["1", "⋮", "missing"], Bool[0, 0, 1])

    # Without :limit every row and column prints, as for arrays.
    all30 = Table(; (Symbol("c", i) => collect(1:30) for i in 1:30)...)
    out = plain(all30; size = (10, 40), limit = false)
    @test count("\n", out) == 3 + 30
    @test !occursin("⋮", out) && !occursin("more column", out)
    @test split(out, "\n")[end] == " " * join(fill(lpad("30", 5), 30), "  ")
    # ... and with :limit the same table is cut.
    @test occursin("⋮", plain(all30; size = (10, 40)))

    # Long nullable labels keep "?": 18 columns, "…", "?".
    u = Union{Missing,Int64,String}[1, "a", missing]
    @test plain(Table(; u)) == lines(
        "3×1 Table", " u", " Union{Int64, Strin…?", " " * "─"^20,
        " 1", " a", " missing")

    # Names are escaped like cells; no raw ANSI escape remains.
    @test plain(Table(; var"a\nb" = [1])) == lines(
        "1×1 Table", "  a\\nb", " Int64", " " * "─"^5, "     1")
    ansi = plain(Table(; var"\e[31mred" = [1]))
    @test ansi == lines(
        "1×1 Table", " \\e[31mred", " " * " "^4 * "Int64", " " * "─"^9,
        " " * " "^8 * "1")
    @test !occursin("\e", ansi)
    wide_names = Table(; abcdefghijkl = [1], var"b\nc" = ["abcdefghijklmnop"])
    @test split(plain(wide_names; size = (24, 25)), "\n")[end] ==
        "… and 1 more column: b\\nc"

    # A huge cell value is limited before it is printed in full.
    @test TableOps._cell(collect(1.0:10^5)) == "[1.0, 2.0, 3.0, 4.0…"
    @test occursin("…", TableOps._plain(collect(1:1000)))
    @test length(TableOps._plain(collect(1.0:10^5))) < 300
    @test length(plain(Table(; v = [collect(1.0:10^5) for _ in 1:3]))) < 300

    # Inside containers the compact form is used.
    two = Table(; a = [1, 2], b = ["x", "y"])
    @test sprint(show, [two, two]) == "Table[2×2 Table, 2×2 Table]"
    @test sprint(show, (a = two,)) == "(a = 2×2 Table,)"

    # Lazy columns (views, ranges) print values, right-aligned.
    @test plain(Table(; v = view(collect(1:10), 3:5), r = 1:3)) == lines(
        "3×2 Table",
        "     v      r",
        " Int64  Int64",
        " " * "─"^12,
        "     3      1",
        "     4      2",
        "     5      3")
end

@testset "glimpse" begin
    s30 = "abcdefghijklmnopqrstuvwxyz0123"
    function glimpse_str(x; size = (24, 80))
        b = IOBuffer()
        @test glimpse(IOContext(b, :displaysize => size), x) === nothing
        String(take!(b))
    end
    t = Table(; store = ["A", "A", "B"], date = [1, 2, 1],
                revenue = [10.0, missing, 5.0])
    @test glimpse_str(t) == join([
        "3×3 Table",
        " store    String    A, A, B",
        " date     Int64     1, 2, 1",
        " revenue  Float64?  10.0, missing, 5.0"], "\n") * "\n"
    @test glimpse(devnull, (a = [1],)) === nothing
    err = try glimpse(devnull, 1) catch e e end
    @test err isa ArgumentError
    @test startswith(err.msg, "glimpse: input is not a Tables.jl table. Got Int64.")
    @test glimpse_str((a = [1, 2],)) == "2×1 Table\n a  Int64  1, 2\n"
    @test glimpse_str(Table()) == "0×0 Table\n"
    @test glimpse_str(Table(; a = Int[])) == "0×1 Table\n a  Int64\n"

    # 200 values in 40 columns: prefix is 11 wide, 29 remain.
    # 1 to 9 take 25; with 10 (29 wide) ", …" cannot fit.
    @test glimpse_str(Table(; x = collect(1:200)); size = (24, 40)) ==
        "200×1 Table\n x  Int64  1, 2, 3, 4, 5, 6, 7, 8, 9, …\n"
    @test textwidth(split(glimpse_str(Table(; x = collect(1:200)); size = (24, 40)),
        "\n")[2]) == 39
    # All values fit exactly: no "…".
    @test glimpse_str(Table(; x = [1, 2, 3]); size = (24, 18)) ==
        "3×1 Table\n x  Int64  1, 2, 3\n"
    # One column short, the last value is dropped for ", …".
    @test glimpse_str(Table(; x = [1, 2, 3]); size = (24, 17)) ==
        "3×1 Table\n x  Int64  1, …\n"
    # No room for any value: only "…".
    @test glimpse_str(Table(; x = [1, 2, 3]); size = (24, 12)) ==
        "3×1 Table\n x  Int64  …\n"
    # Names and types are capped at 20, cells too.
    @test glimpse_str(Table(; abcdefghijklmnopqrstuvwxy = [s30])) ==
        "1×1 Table\n abcdefghijklmnopqrs…  String  abcdefghijklmnopqrs…\n"
    # Escapes and missing.
    @test glimpse_str(Table(; s = ["a\nb", missing])) ==
        "2×1 Table\n s  String?  a\\nb, missing\n"
    # Different tables pad names and types to the widest entry.
    @test glimpse_str((a = [1], bb = ["x"])) ==
        "1×2 Table\n a   Int64   1\n bb  String  x\n"

    # Colour: only missing is grey; padding and width are plain.
    b = IOBuffer()
    glimpse(IOContext(b, :displaysize => (24, 80), :color => true),
        Table(; a = [1, missing], s = ["missing", "x"]))
    out = String(take!(b))
    @test out == "2×2 Table\n a  Int64?  1, \e[90mmissing\e[39m\n" *
        " s  String  missing, x\n"
    @test !occursin("\e", glimpse_str(Table(; a = [1, missing])))
    # A cut line keeps the grey value and a plain ", …" tail.
    b = IOBuffer()
    glimpse(IOContext(b, :displaysize => (24, 23), :color => true),
        Table(; a = [missing, 1, 2]))
    @test String(take!(b)) == "3×1 Table\n a  Int64?  \e[90mmissing\e[39m, …\n"

    # Names are escaped in the name column too.
    @test glimpse_str(Table(; var"a\nb" = [1])) == "1×1 Table\n a\\nb  Int64  1\n"
    @test !occursin("\e", glimpse_str(Table(; var"\e[31mred" = [1])))
    @test glimpse_str(Table(; u = Union{Missing,Int64,String}[1])) ==
        "1×1 Table\n u  Union{Int64, Strin…?  1\n"
end

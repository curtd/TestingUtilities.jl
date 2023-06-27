module TestingUtilitiesDataFramesExt 
    using TestingUtilities, DataFrames, PrettyTables 

    function crayon_from_style(; matching::Bool)
        if matching 
            style = TestingUtilities.show_diff_matching_style
            if isempty(style)
                style = TestingUtilities._show_diff_matching_style_default()
            end
        else 
            style = TestingUtilities.show_diff_differing_style
            if isempty(style)
                style = TestingUtilities._show_diff_differing_style_default()
            end
        end
        kwargs = []
        keys = first.(style)
        index = findfirst(==(:color), keys)
        if !isnothing(index) && (val = last(style[index]); val isa Symbol || val isa Integer || val isa NTuple{3,Integer} || val isa UInt32)
            push!(kwargs, :foreground => val)
        end
        for f in fieldnames(Crayon)
            index = findfirst(==(f), keys)
            if !isnothing(index) && (val = last(style[index]); val isa Bool)
                push!(kwargs, f => val)
            end
        end
        return Crayon(; kwargs...)
    end

    function TestingUtilities.show_diff(expected::AbstractDataFrame, result::AbstractDataFrame; expected_name="expected", result_name="result", io=stderr, compact::Bool=true, kwargs...)
        ctx = IOContext(io, :compact => compact)
        has_colour = get(io, :color, false)
        expected_names = propertynames(expected)
        result_names = propertynames(result)
        not_in_result_names = setdiff(expected_names, result_names)
        not_in_expected_names = setdiff(result_names, expected_names)
        sym_diff = union(not_in_result_names, not_in_expected_names)
        if isempty(sym_diff)
            expected_nrows = nrow(expected)
            result_nrows = nrow(result)
            if expected_nrows == result_nrows 
                max_rows_to_show, max_cols_to_show = TestingUtilities.show_diff_df_max_nrows_ncols[]
                
                max_rows_to_show = max(1, max_rows_to_show)
                max_cols_to_show = max(1, max_cols_to_show)

                differing_rows = Int[]
                for (row_num,(row_expected, row_result)) in enumerate(zip(eachrow(expected), eachrow(result)))
                    if !isequal(row_expected, row_result)
                        push!(differing_rows, row_num)
                    end
                    length(differing_rows) == max_rows_to_show && break 
                end
                n_differing_rows = length(differing_rows)
                difference_df = DataFrame()
                difference_df[!,:row_num] = vec(vcat(differing_rows', repeat([nothing],1, n_differing_rows)))
                difference_df[!,:df] = repeat([expected_name, result_name], length(differing_rows))
                for col in expected_names 
                    difference_df[!, col] = vec(vcat(reshape(expected[differing_rows, col], (1, n_differing_rows)), reshape(result[differing_rows, col], (1, n_differing_rows))))
                end

                matching_crayon = crayon_from_style(; matching=true)
                differing_crayon = crayon_from_style(; matching=false)
                 
                highlight_diff = function(h, data, i, j)
                    if mod(i, 2) == 1
                        if isequal(data[i,j], data[i+1,j])
                            return matching_crayon
                        else
                            return differing_crayon
                        end
                    else
                        return highlight_diff(h, data, i-1, j)
                    end
                end

                highlighters = Highlighter((data,i,j) -> j > 2, highlight_diff)
                formatters = (v, i, j) -> j == 1 && isnothing(v) ? "" : v
                println(ctx, "Reason: Mismatched values")
                pretty_table(ctx, difference_df; highlighters, formatters)
            else
                println(ctx, "Reason: `nrow($expected_name) != nrow($result_name)`")
                p = TestingUtilities.PrintAligned("`nrow($expected_name)`", "`nrow($result_name)`"; separator=" = ")
                p(ctx, 1)
                println(ctx, expected_nrows)
                p(ctx, 2)
                println(ctx, result_nrows)
            end
        else 
            println(ctx, "Reason: `propertynames($expected_name) != propertynames($result_name)`")
            common_columns = [name for name in expected_names if name in result_names]
            
            p = TestingUtilities.PrintAligned("`propertynames($expected_name)`", "`propertynames($result_name)`"; separator=" = ")
            p(ctx, 1)
            print(ctx, "{")
          
            TestingUtilities.show_maybe_styled(ctx, join([repr(s) for s in common_columns], ", "); has_colour, is_matching=true)
          
            if !isempty(common_columns) && !isempty(not_in_result_names)
                print(ctx, ", ")
            end
            TestingUtilities.show_maybe_styled(ctx, join( [repr(s) for s in not_in_result_names], ", "); has_colour, is_matching=false)
            println(ctx, "}")

            p(ctx, 2)
            print(ctx, "{")
            TestingUtilities.show_maybe_styled(ctx, join([repr(s) for s in common_columns], ", "); has_colour, is_matching=true)
            if !isempty(common_columns) && !isempty(not_in_expected_names)
                print(ctx, ", ")
            end
            TestingUtilities.show_maybe_styled(ctx, join([repr(s) for s in not_in_expected_names], ", "); has_colour, is_matching=false)
            println(ctx, "}")
        end
        return true
    end

    TestingUtilities.will_show_diff(expected::AbstractDataFrame, result::AbstractDataFrame) = true
end
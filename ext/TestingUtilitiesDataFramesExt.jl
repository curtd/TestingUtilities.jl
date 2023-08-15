module TestingUtilitiesDataFramesExt 
    using TestingUtilities, DataFrames, PrettyTables 

    const pretty_table_kwarg_keys = (:alignment, :backend, :cell_alignment, :cell_first_line_only, :compact_printing, :formatters, :header, :header_alignment, :header_cell_alignment, :limit_printing, :max_num_of_columns, :max_num_of_rows, :renderer, :row_labels, :row_label_alignment, :row_label_column_title, :row_number_column_title, :show_header, :show_row_number, :show_subheader, :title, :title_alignment)
    const pretty_table_kwarg_keys_text = (pretty_table_kwarg_keys..., :alignment_anchor_fallback, :alignment_anchor_fallback_override, :alignment_anchor_regex, :autowrap, :body_hlines, :body_hlines_format, :columns_width, :crop, :Crop_subheader, :continuation_row_alignment, :display_size, :ellipsis_line_skip, :equal_columns_width, :highlighters, :hlines, :linebreaks, :maximum_columns_width, :minimum_columns_width, :newline_at_end, :overwrite, :reserved_display_lines, :row_number_alignment, :show_omitted_cell_summary, :tf, :title_autowrap, :title_same_width_as_table, :vcrop_mode, :vlines, :border_crayon, :header_crayon, :omitted_cell_summary_crayon, :row_label_crayon, :row_label_header_crayon, :row_number_header_crayon, :subheader_crayon, :text_crayon, :title_crayon)

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

    struct TruncatedValue end 
    PrettyTables.compact_type_str(::Type{TruncatedValue}) = ""

    function show_truncated_df(io::IO, df::AbstractDataFrame; max_num_rows_cols::Tuple{Int,Int} = TestingUtilities.show_df_max_nrows_ncols[], kwargs...)
        max_num_of_rows, max_num_of_columns = max.(1, max_num_rows_cols)
        num_rows = nrow(df)
        num_cols = ncol(df)
        truncate_to_rows = min(num_rows, max_num_of_rows)
        truncate_to_cols = min(num_cols, max_num_of_columns)

        row_indices = 1:(truncate_to_rows + (num_rows > max_num_of_rows ? 1 : 0))
        col_indices = 1:(truncate_to_cols + (num_cols > max_num_of_columns ? 1 : 0))

        df_to_show = df[row_indices, col_indices]
        if num_cols > max_num_of_columns
            rename!(df_to_show, (truncate_to_cols+1) => Symbol("…"))
            df_to_show[!, Symbol("…")] = [TruncatedValue() for _ in row_indices]
        end

        if haskey(kwargs, :formatters)
            _formatter = kwargs[:formatters]
        else
            _formatter = (v,i,j) -> string(v) 
        end
        if haskey(kwargs, :highlighters)
            _highlighters = kwargs[:highlighters]
            highlighter_f = function(data, i, j)
                ((i == truncate_to_rows + 1) || (j == truncate_to_cols + 1)) && return false 
                return _highlighters.f(data, i, j)
            end
            highlighter_fd = _highlighters.fd 
            highlighter_crayon = _highlighters.crayon
            highlighters = Highlighter(highlighter_f, highlighter_fd, highlighter_crayon)
        else
            highlighters = Highlighter((data,i,j) -> false, crayon"white")
        end
        formatters = function(v,i,j)
            if i == truncate_to_rows + 1
                if j ≤ truncate_to_cols
                    return "⋮"
                else
                    return ""
                end
            elseif i == 1
                if j == truncate_to_cols + 1
                    return "⋯"
                else
                    return _formatter(v,i,j)
                end
            elseif j == truncate_to_cols + 1
                return ""
            else
                return _formatter(v,i,j)
            end
        end
        return pretty_table(io, df_to_show; (k => v for (k, v) in pairs(kwargs) if k ∈ pretty_table_kwarg_keys_text)..., highlighters, formatters)
    end

    function TestingUtilities.show_diff(::TestingUtilities.StructTypeCat, ctx::IOContext, expected::AbstractDataFrame, result::AbstractDataFrame; expected_name="expected", result_name="result", max_num_rows_cols::Tuple{Int,Int} = TestingUtilities.show_diff_df_max_nrows_ncols[], results_printer::Union{TestingUtilities.TestResultsPrinter, Nothing}=nothing, differing_cols_only::Bool=false, kwargs...)
        has_colour = get(ctx, :color, false)
        expected_names = propertynames(expected)
        result_names = propertynames(result)
        not_in_result_names = setdiff(expected_names, result_names)
        not_in_expected_names = setdiff(result_names, expected_names)
        sym_diff = union(not_in_result_names, not_in_expected_names)
        if isempty(sym_diff)
            expected_nrows = nrow(expected)
            result_nrows = nrow(result)
            if expected_nrows == result_nrows 
                max_num_of_rows, max_num_of_columns = max.(1, max_num_rows_cols)
                max_num_of_columns_plus_headers = max_num_of_columns+2
                differing_rows = Int[]
                differing_cols = Set{Symbol}()
                for (row_num,(row_expected, row_result)) in enumerate(zip(eachrow(expected), eachrow(result)))
                    if !isequal(row_expected, row_result)
                        push!(differing_rows, row_num)
                        for col in expected_names 
                            if !isequal(row_expected[col], row_result[col])
                                push!(differing_cols, col)
                            end
                        end
                    end
                    length(differing_rows) == max_num_of_rows+1 && break 
                end
                if length(differing_rows) == max_num_of_rows+1
                    pop!(differing_rows)
                    has_more_differing_rows = true
                else
                    has_more_differing_rows = false 
                end

                # If there are more agreeing columns than number of columns we can display, or the first `max_num_of_columns` we can display are agreeing columns, only show differing columns
                agreeing_columns = setdiff(expected_names, differing_cols)
                if length(agreeing_columns) ≥ max_num_of_columns || length(Int[i for (i, col) in enumerate(expected_names) if col in agreeing_columns]) ≥ max_num_of_columns
                    differing_cols_only = true
                end
                n_differing_rows = length(differing_rows)
                difference_dfs = DataFrame[]
                if differing_cols_only
                    for row_num in differing_rows 
                        difference_df = DataFrame()
                        difference_df[!,:row_num] = [row_num, nothing]
                        difference_df[!,:df] = [expected_name, result_name]
                        for col in expected_names 
                            if !isequal(expected[row_num, col], result[row_num, col])
                                difference_df[!, col] = [expected[row_num, col], result[row_num, col]]
                            end
                        end
                        push!(difference_dfs, difference_df)
                    end
                else
                    difference_df = DataFrame()
                    difference_df[!,:row_num] = vec(vcat(differing_rows', repeat([nothing],1, n_differing_rows)))
                    difference_df[!,:df] = repeat([expected_name, result_name], length(differing_rows))
                    for col in expected_names 
                        difference_df[!, col] = vec(vcat(reshape(expected[differing_rows, col], (1, n_differing_rows)), reshape(result[differing_rows, col], (1, n_differing_rows))))
                    end
                    push!(difference_dfs, difference_df)
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
                for df in difference_dfs
                    show_truncated_df(ctx, df; highlighters, formatters, max_num_rows_cols=(max_num_of_rows, max_num_of_columns_plus_headers))
                end
                if length(difference_dfs) == n_differing_rows && has_more_differing_rows
                    println(ctx, "⋮ ⋮ ⋮")
                end
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

    TestingUtilities.show_value(ctx::IOContext, value::AbstractDataFrame; max_num_rows_cols::Tuple{Int,Int} =  TestingUtilities.show_df_max_nrows_ncols[], kwargs...) = show_truncated_df(ctx, value; max_num_rows_cols, kwargs...)

    TestingUtilities.should_print_differing_fields_header(::Type{<:AbstractDataFrame}) = false
end
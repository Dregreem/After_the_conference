function prepareMonthlyCSV(loc_name)
%PREPAREMONTHLYCSV  Build {LOC}_MonthlyAvg.csv from raw PVGIS monthly files.
%
%  Reads the 12 tab-delimited PVGIS monthly files for the given city and
%  writes a clean 288-row (12 months x 24 hours) CSV used by
%  CompareYield_TMY_Temp.m for T2m and WS10m lookups.
%
%  Supported city names: 'ANKARA', 'ANTALYA', 'ISTANBUL'

loc_upper = upper(strtrim(loc_name));

switch loc_upper
    case 'ANKARA'
        data_dir = 'Ankara_Data';
        pat      = 'Dailydata_39.790_32.810_SA3_%02d_0deg_0deg.csv';
    case 'ANTALYA'
        data_dir = 'Antalya_Data';
        pat      = 'Dailydata_36.200_29.640_SA3_%02d_0deg_0deg.csv';
    case 'ISTANBUL'
        data_dir = 'YTU_data';
        pat      = 'Dailydata_41.050_29.010_SA3_%02d_0deg_0deg.csv';
    otherwise
        error('Unknown location "%s". Supported: ANKARA, ANTALYA, ISTANBUL.', loc_upper);
end

month_names = {'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'};
default_WS  = 1.5;   % m/s fallback (PVGIS monthly files have no wind column)

out_rows = cell(12 * 24, 1);
row_idx  = 0;

for m = 1:12
    fpath = fullfile(data_dir, sprintf(pat, m));
    if ~isfile(fpath)
        error('Missing monthly file: %s', fpath);
    end

    fid = fopen(fpath, 'r');
    if fid < 0
        error('Cannot open: %s', fpath);
    end
    raw   = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    lines = raw{1};

    % Find the column-header line that contains 'time'
    hdr_line = -1;
    for li = 1:numel(lines)
        if contains(lower(lines{li}), 'time')
            hdr_line = li;
            break;
        end
    end
    if hdr_line < 0
        error('Cannot find data header in: %s', fpath);
    end

    for hh = 0:23
        data_line = lines{hdr_line + 1 + hh};
        parts = strsplit(strtrim(data_line), sprintf('\t'));
        if numel(parts) < 5
            parts = strsplit(strtrim(data_line));
        end
        % columns: time, G(i), Gb(i), Gd(i), T2m
        GHI    = str2double(parts{2});
        Gb_hor = str2double(parts{3});
        Diff   = str2double(parts{4});
        T2m    = str2double(parts{5});

        row_idx = row_idx + 1;
        out_rows{row_idx} = sprintf('%d,%s,%d,%.4f,%.4f,%.4f,%.4f,%.4f', ...
            m, month_names{m}, hh, GHI, Gb_hor, Diff, T2m, default_WS);
    end
end

out_file = sprintf('%s_MonthlyAvg.csv', loc_upper);
fid = fopen(out_file, 'w');
if fid < 0
    error('Cannot write output file: %s', out_file);
end
fprintf(fid, 'Month,MonthName,Hour,GHI,Gb_hor,Diffuse,T2m,WS10m\n');
for r = 1:row_idx
    fprintf(fid, '%s\n', out_rows{r});
end
fclose(fid);

fprintf('  done: %s  (%d rows)\n', out_file, row_idx);
end

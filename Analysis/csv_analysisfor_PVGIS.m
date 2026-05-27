function processAndSavePVGIS(inputFile, outputFile)
% PROCESSANDSAVEPVGIS Reads raw PVGIS CSV, extracts Time, Global Irradiance, 
% and Sun Height, and saves them to a new, clean CSV file.
%
% Usage: processAndSavePVGIS('tmy_hourly.csv', 'clean_solar_data.csv')

    % 1. Dynamically find the header line to bypass metadata
    fid = fopen(inputFile, 'rt');
    if fid == -1
        error('Cannot open input file: %s', inputFile);
    end
    
    headerLineNum = 1;
    while ~feof(fid)
        currentLine = fgetl(fid);
        if startsWith(currentLine, 'time,')
            break;
        end
        headerLineNum = headerLineNum + 1;
    end
    fclose(fid);

    % 2. Set up import options
    opts = detectImportOptions(inputFile, 'NumHeaderLines', headerLineNum - 1);
    opts.VariableNamingRule = 'preserve';
    
    % 3. Read the raw data
    T_raw = readtable(inputFile, opts);

    % Remove trailing junk rows at the bottom (copyright text, etc.)
    if iscell(T_raw.time)
        T_raw(cellfun(@isempty, T_raw.time), :) = [];
    end

    % 4. Parse Time
    try
        cleanTime = datetime(T_raw.time, 'InputFormat', 'yyyyMMdd:HHmm');
    catch
        cleanTime = datetime(T_raw.time); 
    end
    
    % 5. Extract/Calculate Global Irradiance
    varNames = T_raw.Properties.VariableNames;
    
    if ismember('G(i)', varNames)
        globalIrradiance = ensureDouble(T_raw.("G(i)"));
    elseif ismember('Gb(i)', varNames) && ismember('Gd(i)', varNames)
        beam = ensureDouble(T_raw.("Gb(i)"));
        diffuse = ensureDouble(T_raw.("Gd(i)"));
        if ismember('Gr(i)', varNames)
            reflected = ensureDouble(T_raw.("Gr(i)"));
            globalIrradiance = beam + diffuse + reflected;
        else
            globalIrradiance = beam + diffuse;
        end
    else
        error('Could not find Irradiance data columns in the raw file.');
    end
    
    % 6. Extract Sun Elevation
    if ismember('H_sun', varNames)
        sunElevation = ensureDouble(T_raw.H_sun);
    else
        sunElevation = zeros(height(T_raw), 1); % Fallback
        disp('Warning: H_sun column not found, filling with zeros.');
    end
    
    % 7. Create the new clean table
    T_clean = table(cleanTime, globalIrradiance, sunElevation, ...
        'VariableNames', {'Time', 'Global_Irradiance_W_m2', 'Sun_Elevation_deg'});
    
    % 8. Write to the new CSV file
    writetable(T_clean, outputFile);
    
    fprintf('Successfully generated new clean file: %s\n', outputFile);
end

% Helper function to prevent cell-array casting issues
function outArr = ensureDouble(inCol)
    if iscell(inCol)
        outArr = str2double(inCol);
    else
        outArr = double(inCol);
    end
end
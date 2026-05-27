function AnalyzeIrradianceProfiles_NoPrompt(loc_name, data_mode, results_base)
%% ANALYZEIRRADIANCEPROFILES_NOPROMPT
%  AnalyzeIrradianceProfiles'i onay sormadan çalıştırır.
%  RunAll.m tarafından tüm lokasyonlar hazırlandıktan sonra
%  toplu onay aşamasından önce çağrılır.

if nargin < 2, data_mode    = 'HOURLY'; end
if nargin < 3, results_base = '';       end

AnalyzeIrradianceProfiles(loc_name, data_mode, results_base);

end

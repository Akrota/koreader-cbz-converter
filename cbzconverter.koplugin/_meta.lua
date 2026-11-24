-- Beschreibung auf Deutsch oder Englisch, je nach KOReader-Sprache
local ok, lang = pcall(function() return G_reader_settings:readSetting("language") end)
local de = ok and type(lang) == "string" and lang:sub(1, 2):lower() == "de"
return {
    fullname = de and "CBZ-Konverter" or "CBZ converter",
    description = de
        and "Wandelt CBR, CB7, CBT, EPUB, MOBI/AZW und PDF direkt auf dem Gerät in CBZ um (Bilder bleiben außer bei PDF unverändert)."
        or "Converts CBR, CB7, CBT, EPUB, MOBI/AZW and PDF to CBZ right on the device (images stay unchanged except for PDF).",
    version = "0.1.0",
}

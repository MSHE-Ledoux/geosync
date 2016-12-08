set schema 'geonetwork';
select count(*) from operationallowed;
INSERT INTO operationallowed SELECT 1, metadata.id, 1 FROM metadata WHERE data ILIKE '%fouilles_chailluz__pt_limsit_sra%' ;
INSERT INTO operationallowed SELECT 1, metadata.id, 5 FROM metadata WHERE data ILIKE '%fouilles_chailluz__pt_limsit_sra%' ;

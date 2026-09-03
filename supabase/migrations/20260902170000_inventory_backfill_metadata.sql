-- Backfill brand / variety / packaging from the item names.
--
-- Derived by reading all 195 live item names against the rules in
-- docs/inventory_naming_conventions.md, then reviewed by the business owner on
-- a published proposal page before anything was written.
--
-- PURELY ADDITIVE. Only these four columns are set:
--   brand, variety, packaging_size, packaging_size_unit
-- item_name is NOT touched -- not to strip sizes, not to fix the known typos
-- («500 حم», «ا كجم», «100 حبه»). The size of one piece (330 مل, 1 كجم) stays
-- inside the name by the owner's explicit decision; only the pack COUNT moves
-- into packaging_size. Shortening names would degrade AI matching, which reads
-- item_name and nothing else until LocalItemMatcher is wired to these columns.
--
-- The A*B rule, confirmed by the owner against real cartons: the SMALLER number
-- is packs-per-carton, the LARGER is pieces-per-pack, and packaging_size takes
-- the larger. Position is not reliable -- the larger number is first in
-- «شد 50*10» and second in «شد 6 *40». Verified mechanically across all 17
-- multiplication rows. Exceptions: a side carrying a weight/volume unit is the
-- piece size («شد 10*500 جم» -> 10), and product identifiers are not counts at
-- all («نسكافيه 3*1», filter cone sizes «1*2»/«1*4»).
--
-- Written as direct UPDATEs rather than through inventory_bulk_update_items on
-- purpose. That RPC replaces the whole row from its payload -- it would need
-- every other column echoed back or it would blank sku/category/description and
-- reset min_quantity -- and its role check rejects a migration connection
-- outright, since get_user_role() is NULL without a JWT. The trade-off is that
-- these writes produce no inventory_audit_log rows; acceptable for a one-time
-- metadata backfill that changes no quantity.
--
-- 8 rows have their brand/variety deliberately LEFT NULL pending the owner's
-- ruling on whether the name carries a brand or merely a descriptor: «بن»,
-- «ديلوكس», «فلة», «سوبر», «حاجة», «ماس», «أبو حصان», and which of
-- القصيم/الضيف owns the brand on the vacuum-packed dates. Of those, 1
-- still appears below because it has a packaging count worth applying now
-- (فلتر قهوة بن - 100 حبة); the other 7 carry nothing BUT the
-- disputed brand, so they get no statement at all and stay entirely NULL.
--
-- A further 5 rows have nothing in the name to extract at all
-- (زنجبيل، صقعي، كركديه، سحلب، قرنفل).

UPDATE "public"."inventory" SET brand = NULL, variety = 'بلاستيك أسود', packaging_size = 20, packaging_size_unit = 'حبة'
  WHERE "id" = 'a54c1476-caf9-4dcb-b422-5ff3b6856fd9';  -- سكينة بلاستيك اسود - 1 * 20 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'بلاستيك أسود', packaging_size = 20, packaging_size_unit = 'حبة'
  WHERE "id" = '46578bf2-15c4-45fd-be95-b38645016eaa';  -- شوكة بلاستيك اسود - 1 * 20 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'بلاستيك أسود مغلف', packaging_size = 500, packaging_size_unit = 'حبة'
  WHERE "id" = 'c14324d2-caa5-48b2-925a-8ed975cf9909';  -- شوكة بلاستيك مغلف اسود - شد 500 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'خشب', packaging_size = 30, packaging_size_unit = 'حبة'
  WHERE "id" = 'fda74b1d-7552-4a36-be29-748fd5fa6ab8';  -- شوكة خشب 160 مل - شد 30
UPDATE "public"."inventory" SET brand = NULL, variety = 'شفاف', packaging_size = 1000, packaging_size_unit = 'حبة'
  WHERE "id" = '51db7d44-2c76-4da1-b8a5-9031a6af2580';  -- شوكة طعام شفاف - 1000 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'بلاستيك شفاف دائري', packaging_size = 300, packaging_size_unit = 'حبة'
  WHERE "id" = 'a0c9dbff-1920-4be8-b090-11d176ec3a9f';  -- صحن بلاستيك صياب دائري شفاف - شد 300
UPDATE "public"."inventory" SET brand = NULL, variety = 'بلاستيك مستطيل صغير', packaging_size = 1000, packaging_size_unit = 'حبة'
  WHERE "id" = 'be7469ea-d576-4729-b9f3-f22314fd9d01';  -- صحن بلاستيك مستطيل صغير - 1000 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'بلاستيك مستطيل كبير', packaging_size = 1000, packaging_size_unit = 'حبة'
  WHERE "id" = '5c82ae13-74f6-44ed-8727-76acfcd553ae';  -- صحن بلاستيك مستطيل كبير - 1000 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'بلاستيك مستطيل وسط', packaging_size = 1000, packaging_size_unit = 'حبة'
  WHERE "id" = '9cbc9609-717c-4be6-b20f-87b81142090c';  -- صحن بلاستيك مستطيل وسط - 1000 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'بلاستيك مقاس 18', packaging_size = 50, packaging_size_unit = 'حبة'
  WHERE "id" = '560ad542-ac92-4591-9345-299054c9b53b';  -- صحن بلاستيك مقاس 18 - شد 50*10 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'ورق', packaging_size = 10, packaging_size_unit = 'حبة'
  WHERE "id" = '968ff4d5-56c5-4e2d-ad40-dbca087ec2fc';  -- صحن ورق 9 اونص 4M - شد 10
UPDATE "public"."inventory" SET brand = NULL, variety = 'ورق كرافت بني وأسود مقاس 3', packaging_size = 40, packaging_size_unit = 'حبة'
  WHERE "id" = 'a8b83e54-caba-4282-819a-b226aa0bf4c5';  -- صحن ورق كرافت بني واسود مقاس 3 - شد 40*25 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'دبل', packaging_size = 500, packaging_size_unit = 'حبة'
  WHERE "id" = 'd4ddab27-1c58-42f4-a241-889ab4e1c89a';  -- غطاء كاسات 8 اونص دبل - شد 500 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'سنجل أبيض', packaging_size = 1000, packaging_size_unit = 'حبة'
  WHERE "id" = 'a46b3cdc-7d48-40c2-a6ee-c08ab70a53a7';  -- كاسات ابيض سنجل - 7 اونص 1000 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'دبل أسود', packaging_size = 1000, packaging_size_unit = 'حبة'
  WHERE "id" = 'ce39386d-bc9b-45f0-b461-327e78299b88';  -- كاسات اسود دبل - 4 اونص 1000 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'سنجل أسود', packaging_size = 1000, packaging_size_unit = 'حبة'
  WHERE "id" = 'd9e7b115-e59f-426f-bfde-057c0782dd5e';  -- كاسات اسود سنجل - 8 اونص 1000 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'بشعار بنك المنشآت', packaging_size = 1000, packaging_size_unit = 'حبة'
  WHERE "id" = '838d6a8b-965e-47cc-807b-77c50f123d97';  -- كاسات بنك المنشات - 8 اونص 1000 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'بني مضلع', packaging_size = 500, packaging_size_unit = 'حبة'
  WHERE "id" = '3e65a71d-088d-4ade-be76-20b7afa585ce';  -- كاسات بني مضلع - 8 اونص 500 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'دبل أبيض ورق', packaging_size = 1000, packaging_size_unit = 'حبة'
  WHERE "id" = '84f65444-f126-4afd-b454-e1f2db461883';  -- كاسات دبل ابيض ورق 4 اونص 1000 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'دبل أبيض ورق', packaging_size = 500, packaging_size_unit = 'حبة'
  WHERE "id" = '0a213a0b-6518-447d-9443-df95563386bf';  -- كاسات دبل ابيض ورق 8 اونص 500 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'دبل بني مضلع', packaging_size = 1000, packaging_size_unit = 'حبة'
  WHERE "id" = 'd1028606-2ac5-42a5-95e5-7c8ce0637c19';  -- كاسات دبل بني مضلع - 4 اونص شد 1000 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'سنجل أبيض', packaging_size = 1000, packaging_size_unit = 'حبة'
  WHERE "id" = 'ddf64a9a-55f5-40f7-a3c9-816bc47c9f24';  -- كاسات سنجل ابيض - 4 اونص 1000 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'سنجل أبيض', packaging_size = 1000, packaging_size_unit = 'حبة'
  WHERE "id" = '0470da97-d5e2-465f-a403-126d03cc6695';  -- كاسات سنجل ابيض - 8 اونص 1000 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'سنجل بني مضلع', packaging_size = 1000, packaging_size_unit = 'حبة'
  WHERE "id" = '38d5ffe5-76a2-4710-a078-b82978c1b19e';  -- كاسات سنجل بني مضلع - 4 اونص شد 1000 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'بلاستيك أسود', packaging_size = 20, packaging_size_unit = 'حبة'
  WHERE "id" = 'b39a62ad-1b20-44ac-91a4-3bfdb9c9b882';  -- ملاعق بلاستيك اسود - 1 * 20 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'خشب', packaging_size = 30, packaging_size_unit = 'حبة'
  WHERE "id" = '669f4537-6ea2-403e-a98e-d4a63d0b28d9';  -- ملاعق خشب 160 مل - شد 30
UPDATE "public"."inventory" SET brand = NULL, variety = 'شاي شفاف', packaging_size = 1000, packaging_size_unit = 'حبة'
  WHERE "id" = '54da74e3-e71a-4643-a69b-516d0ac99a7b';  -- ملاعق شاي شفاف - 1000 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'طعام شفاف', packaging_size = 1000, packaging_size_unit = 'حبة'
  WHERE "id" = 'fa28dee5-e21a-4456-817e-6e5a439edbd6';  -- ملاعق طعام شفاف - 1000 حبة
UPDATE "public"."inventory" SET brand = 'أبو قوس', variety = 'كامل الدسم', packaging_size = 96, packaging_size_unit = 'حبة'
  WHERE "id" = '2533152f-8309-4dc0-ba18-6705c0f3eca7';  -- حليب ابو قوس كامل الدسم 170 جم - شد 96
UPDATE "public"."inventory" SET brand = 'المراعي', variety = NULL, packaging_size = 18, packaging_size_unit = 'حبة'
  WHERE "id" = '85b4b75d-ec0f-4dfb-b9a9-a128d7584b29';  -- حليب المراعي 200 مل - شد 18 حبة
UPDATE "public"."inventory" SET brand = 'المراعي', variety = 'قليل الدسم', packaging_size = 12, packaging_size_unit = 'حبة'
  WHERE "id" = '8b55e63b-3fa7-488c-bfb3-d4f281b9fc04';  -- حليب المراعي قليل الدسم 1 لتر - شد 12 حبة
UPDATE "public"."inventory" SET brand = 'المراعي', variety = 'كامل الدسم', packaging_size = 12, packaging_size_unit = 'حبة'
  WHERE "id" = 'a75979e8-22cd-4973-8df5-59f6fa5d08bc';  -- حليب المراعي كامل الدسم 1 لتر - شد 12 حبة
UPDATE "public"."inventory" SET brand = 'بوني', variety = 'شفرات', packaging_size = 50, packaging_size_unit = 'حبة'
  WHERE "id" = 'df717abc-2f11-4bd9-89f8-e89e5632a341';  -- حليب بوني شفرات 50 حبة 15 جم
UPDATE "public"."inventory" SET brand = 'بوني', variety = 'كامل الدسم', packaging_size = 48, packaging_size_unit = 'حبة'
  WHERE "id" = '370bffec-a04a-401d-ba62-37f41203aaea';  -- حليب بوني كامل الدسم 170 مل كرتون - شد 48
UPDATE "public"."inventory" SET brand = 'لونا', variety = 'كامل الدسم', packaging_size = 96, packaging_size_unit = 'حبة'
  WHERE "id" = 'faf43216-4458-45e7-b7c3-53f680e5d44b';  -- حليب لونا كامل الدسم - 170 مل - شد 96
UPDATE "public"."inventory" SET brand = 'نادك', variety = 'قليل الدسم', packaging_size = 12, packaging_size_unit = 'حبة'
  WHERE "id" = '3045b5aa-bde1-4c37-be0d-63b5900d4801';  -- حليب نادك قليل الدسم 1 لتر - شد 12 حبة
UPDATE "public"."inventory" SET brand = 'نادك', variety = 'كامل الدسم', packaging_size = 12, packaging_size_unit = 'حبة'
  WHERE "id" = '416cbd7a-0cf7-4ff5-a567-23417c0def41';  -- حليب نادك كامل الدسم 1 لتر - شد 12 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'طازج كامل الدسم', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'ed8fd646-2ebb-4f2f-b02d-b38c0830d1d2';  -- لبن طازج كامل الدسم 180 مل
UPDATE "public"."inventory" SET brand = 'باسلات', variety = 'مسحوق', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '6079c6f3-7f91-4377-a03a-e7d787210597';  -- مسحوق حليب - باسلات
UPDATE "public"."inventory" SET brand = 'اسيانا', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '426f83ae-d5be-4419-8e49-c48d2a333a03';  -- زعفران اسيانا - 1.50 جم
UPDATE "public"."inventory" SET brand = 'اسيانا', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'cbf07d09-62e1-4cdd-a1dc-721f42fa635d';  -- زعفران اسيانا - 2 جم
UPDATE "public"."inventory" SET brand = 'اسيانا', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'beb5c4f2-ac48-46d3-99c8-a940f881d582';  -- زعفران اسيانا - 5 جم
UPDATE "public"."inventory" SET brand = NULL, variety = 'مطحون', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '41d4f5bb-140e-446a-bf3a-83449a3eeca1';  -- زنجبيل مطحون - 500 جم
UPDATE "public"."inventory" SET brand = 'القصيم', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'a4f458dd-bafe-4963-8cdf-fbedeb65651e';  -- صقعي القصيم كود 44/25
UPDATE "public"."inventory" SET brand = 'القصيم', variety = 'معرم', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '4764a901-8f0c-4d0c-9deb-ac37bf2b6387';  -- صقعي القصيم معرم كود 45/25
UPDATE "public"."inventory" SET brand = NULL, variety = 'إندونيسي', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'eadc3ec9-eba4-4308-9c8d-b998d97932e9';  -- قرنفل اندونيسي - 1 كيلو
UPDATE "public"."inventory" SET brand = NULL, variety = 'بلاستيك', packaging_size = 200, packaging_size_unit = 'حبة'
  WHERE "id" = '4889d1c3-e029-4f0b-bb3c-ab0ed7ba8f33';  -- علبة بلاستيك شد 200
UPDATE "public"."inventory" SET brand = 'المحمدية', variety = 'سكري', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '00c2df7d-4fec-409f-8e3a-6c80ab2371e8';  -- تمر سكري - المحمدية
UPDATE "public"."inventory" SET brand = 'القصيم', variety = 'سكري مغلف فاخر', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '29578fbe-b36d-4ecb-93a2-fe543c5ca851';  -- تمر سكري القصيم مغلف فاخر
UPDATE "public"."inventory" SET brand = 'جلاكسي', variety = 'سكري', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'df41f691-8b5b-4152-872c-705399e1209b';  -- تمر سكري جلاكسي
UPDATE "public"."inventory" SET brand = 'جلاكسي', variety = 'سكري', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '5e32c5a7-6ca2-4e9f-91e4-980de15b98e4';  -- تمر سكري جلاكسي  39/25
UPDATE "public"."inventory" SET brand = 'أطايب التمور', variety = 'سكري مغلف', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'c826fc64-632d-445e-b463-e4aa71fddedc';  -- تمر سكري مغلف - اطايب التمور
UPDATE "public"."inventory" SET brand = 'الضيف', variety = 'سكري مغلف بالحبة', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'd18d4af3-363b-468e-8902-621def6e037c';  -- تمر سكري مغلف بالحبة - الضيف
UPDATE "public"."inventory" SET brand = 'ديلايتس', variety = 'محشي', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '0a275d53-6d15-44b8-ac13-e1c5f9728ddd';  -- تمر محشي ديلايتس
UPDATE "public"."inventory" SET brand = 'القصيم', variety = 'خلاص 2 نجوم', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '08a9d35d-5719-48bd-ac05-860c1e02e117';  -- خلاص القصيم 2 نجوم 1 كيلو
UPDATE "public"."inventory" SET brand = 'القصيم', variety = 'خلاص 4 نجوم باللوز', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '7453f024-bb00-4025-a4cd-37764c70d9dc';  -- خلاص القصيم 4 نجوم باللوز - 500 جم - كرتون
UPDATE "public"."inventory" SET brand = 'القصيم', variety = 'خلاص 5 نجوم باللوز', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '531f3df0-2e6d-4790-bd6d-7d2ce82616d7';  -- خلاص القصيم باللوز 5 نجوم - 500 جم
UPDATE "public"."inventory" SET brand = NULL, variety = 'أصابع أبيض', packaging_size = 1000, packaging_size_unit = 'ظرف'
  WHERE "id" = '1007ae38-dff1-4a25-bb90-b7b62facf443';  -- سكر اصابع ابيض - 1000 ظرف
UPDATE "public"."inventory" SET brand = 'الراحة', variety = 'أصابع أبيض', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '57c6b8d8-5531-49e6-b6e9-bfcc8e097b1b';  -- سكر اصابع الراحة ابيض 400 جم
UPDATE "public"."inventory" SET brand = 'الأسرة', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '324287ec-4f5f-4462-8209-c0bd3d6feedc';  -- سكر الاسرة - 10 كجم
UPDATE "public"."inventory" SET brand = 'الأسرة', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '94bf0830-0b37-4c38-b492-fa2edbd4c093';  -- سكر الاسرة - 5 كجم
UPDATE "public"."inventory" SET brand = 'الأسرة', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'd1777a80-21fa-42df-ab39-ef533c2a7392';  -- سكر الاسرة 1 كجم - حبة
UPDATE "public"."inventory" SET brand = 'ستيفيانا', variety = NULL, packaging_size = 100, packaging_size_unit = 'ظرف'
  WHERE "id" = '1a4bdd86-d4e2-41d8-984d-c397f44197e2';  -- سكر ستيفيانا - 100 ظرف
UPDATE "public"."inventory" SET brand = 'القصيم', variety = 'سكري 4 نجوم', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'a58c8914-d106-42e4-9a8a-1d5f77fccb61';  -- سكري القصيم 4 نجوم - 500 جم - كرتون
UPDATE "public"."inventory" SET brand = 'القصيم', variety = 'سكري', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '502d9ae0-271d-47f6-83fe-e34fd534af24';  -- سكري القصيم رقم 20/25
UPDATE "public"."inventory" SET brand = 'أبو جبل', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'fab5297a-541c-4b0b-93f8-290d2d2349e9';  -- أبو جبل - شاي - 300 جم
UPDATE "public"."inventory" SET brand = 'أبو جبل', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '35827278-d4a3-4fc7-b02a-1ec3200d612d';  -- ابو جبل - شاي - 750 جم
UPDATE "public"."inventory" SET brand = 'أحمد', variety = 'أخضر', packaging_size = 100, packaging_size_unit = 'خيط'
  WHERE "id" = '0653992f-145b-458f-81f1-9c09434a2a24';  -- احمد - شاي اخضر - 100 خيط
UPDATE "public"."inventory" SET brand = 'أحمد', variety = 'إنجليزي', packaging_size = 100, packaging_size_unit = 'خيط'
  WHERE "id" = 'a3018600-108d-4eab-8064-193207267133';  -- احمد - شاي انجليزي - 100 خيط
UPDATE "public"."inventory" SET brand = 'أحمد', variety = 'بابونج وعشب الليمون', packaging_size = 20, packaging_size_unit = 'خيط'
  WHERE "id" = '6e3dc06b-e950-4ead-a0c2-6cf3ffd41057';  -- احمد - شاي بابونج وعشب الليمون 20 خيط
UPDATE "public"."inventory" SET brand = 'الربيع', variety = 'أخضر', packaging_size = 100, packaging_size_unit = 'خيط'
  WHERE "id" = '76a11cbf-63c4-4428-b7c8-8b440b68faaf';  -- الربيع - شاي اخضر 100 خيط
UPDATE "public"."inventory" SET brand = 'الربيع', variety = 'اكسبريس', packaging_size = 100, packaging_size_unit = 'خيط'
  WHERE "id" = '10aaa2fc-4d2c-4f67-b6f8-eeef0e448a3a';  -- الربيع - شاي اكسبريس 100 خيط
UPDATE "public"."inventory" SET brand = 'الربيع', variety = 'أوراق كاملة', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '1e664a47-3986-418b-aa43-7330c95cb4c8';  -- الربيع - شاي اوراق كاملة 1 كيلو
UPDATE "public"."inventory" SET brand = 'الوزة', variety = 'أسود', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'a009c9f1-0c13-43cf-a833-17a2e776bc2a';  -- الوزة - شاي اسود 200 جم
UPDATE "public"."inventory" SET brand = 'الوزة', variety = 'أسود', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '3dd2f6b3-9b74-438a-b12d-5628fe1f346b';  -- الوزة - شاي اسود 300 جم
UPDATE "public"."inventory" SET brand = 'توينجز', variety = 'أحمر', packaging_size = 100, packaging_size_unit = 'كيس'
  WHERE "id" = '96f99dac-afbb-4782-90e6-17e1472a13ca';  -- توينجز - شاي احمر 100 كيس
UPDATE "public"."inventory" SET brand = 'توينجز', variety = 'أخضر', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '953e6737-1ac8-4f8c-a648-08e68a5a7356';  -- توينجز - شاي اخضر
UPDATE "public"."inventory" SET brand = 'باسلات', variety = 'كرك قليل السكر', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '400279d7-1abd-4080-8743-f5ab07f67153';  -- شاي كرك قليل السكر - باسلات
UPDATE "public"."inventory" SET brand = 'كريشو', variety = 'مغلف', packaging_size = 100, packaging_size_unit = 'حبة'
  WHERE "id" = 'f5ea5805-939c-471f-a1b1-1c3735904704';  -- شاي كريشو مغلف 100 حبه
UPDATE "public"."inventory" SET brand = 'كابوس', variety = NULL, packaging_size = 100, packaging_size_unit = 'خيط'
  WHERE "id" = '842459bb-462d-438b-8f13-a323f5b004b8';  -- كابوس - شاي - 100 خيط
UPDATE "public"."inventory" SET brand = 'كابوس', variety = NULL, packaging_size = 25, packaging_size_unit = 'خيط'
  WHERE "id" = '3868ab82-c4ba-422a-a91e-cfee22ca5687';  -- كابوس - شاي - 25 خيط
UPDATE "public"."inventory" SET brand = 'كوفيك', variety = 'عدني', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'd20ae61d-b93a-470d-913b-a1d426aa83d6';  -- كوفيك - شاي عدني - 1 كجم
UPDATE "public"."inventory" SET brand = 'ليبتون', variety = 'أخضر', packaging_size = 100, packaging_size_unit = 'خيط'
  WHERE "id" = '1c298d31-81ac-4294-b3e6-bd331dd824fd';  -- ليبتون - شاي اخضر 100 خيط
UPDATE "public"."inventory" SET brand = 'ليبتون', variety = 'أخضر مغلف', packaging_size = 25, packaging_size_unit = 'خيط'
  WHERE "id" = '8d31d5df-6ab9-41d5-a625-90f7a8769efe';  -- ليبتون - شاي اخضر 25 خيط مغلف
UPDATE "public"."inventory" SET brand = 'ليبتون', variety = 'أخضر هارموني', packaging_size = 20, packaging_size_unit = 'خيط'
  WHERE "id" = '1984c87a-d5d1-4d57-9480-f3538619103b';  -- ليبتون - شاي اخضر هارموني 16*20
UPDATE "public"."inventory" SET brand = 'ليبتون', variety = 'الصفراء', packaging_size = 100, packaging_size_unit = 'خيط'
  WHERE "id" = '98baf533-36f2-4572-a0ae-6702d30e5a5f';  -- ليبتون - شاي الصفراء 100 خيط
UPDATE "public"."inventory" SET brand = 'تويكس', variety = 'صغير', packaging_size = 40, packaging_size_unit = 'حبة'
  WHERE "id" = '386e7025-f7b7-4b03-a344-64e5d5276b7c';  -- تويكس - شيكولاتة صغير شد 6 *40 حبة
UPDATE "public"."inventory" SET brand = 'جلاكسي', variety = 'صغير', packaging_size = 36, packaging_size_unit = 'حبة'
  WHERE "id" = '88689e90-db03-4d15-9dec-7c3fb5cd8425';  -- جلاكسي - شيكولاتة صغير شد 8 *36 حبة
UPDATE "public"."inventory" SET brand = 'جوديفا', variety = 'صغير', packaging_size = 24, packaging_size_unit = 'حبة'
  WHERE "id" = '31a423aa-9ce6-4142-a53c-67033d52a2b5';  -- جوديفاء - شيكولاتة صغير شد 6 *24 حبة
UPDATE "public"."inventory" SET brand = 'سنيكرز', variety = 'صغير', packaging_size = 20, packaging_size_unit = 'حبة'
  WHERE "id" = 'db795925-0e3c-46d3-a751-72a0608ba6d5';  -- سنيكرز - شيكولاتة صغير شد 12 *20 حبة
UPDATE "public"."inventory" SET brand = 'باسلات', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '2f90ea40-188a-4c8d-a69d-23ff9f7e9562';  -- شيكولاتة  باسلات
UPDATE "public"."inventory" SET brand = 'باتشي', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '6a0a2771-9a49-4733-b3a7-7ed0b9760011';  -- شيكولاتة باتشي
UPDATE "public"."inventory" SET brand = 'كوفيك', variety = 'للماكينات', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'e0096353-4d34-4857-8bc3-304369e5c155';  -- كوفيك - شوكولاتة للماكينات 1 كجم
UPDATE "public"."inventory" SET brand = 'كيت كات', variety = 'صغير', packaging_size = 36, packaging_size_unit = 'حبة'
  WHERE "id" = '659cf138-d7fd-4878-9208-be2d2ac7bdbc';  -- كيت كات - شيكولاتة صغير شد 18 *36 حبة
UPDATE "public"."inventory" SET brand = 'نسكويك', variety = 'بودرة', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '197a9a8f-bb0a-40fa-8eb3-47ad647d689f';  -- نسكويك بودرة كبير - ا كيلو
UPDATE "public"."inventory" SET brand = NULL, variety = 'برتقال', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '0215c7a6-f434-427d-b234-d944ac42d5be';  -- عصير البرتقال 200 مل
UPDATE "public"."inventory" SET brand = NULL, variety = 'تفاح', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'ba550258-8cca-4d11-af6a-875d57e5ca6b';  -- عصير التفاح 200 مل
UPDATE "public"."inventory" SET brand = NULL, variety = 'توت مشكل', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '362fe7ff-79d0-4044-92bb-ac5512ddc704';  -- عصير التوت المشكل 200 مل
UPDATE "public"."inventory" SET brand = NULL, variety = 'ليمون', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'e892b29d-5c87-45a1-9864-ebfe6f30d8d6';  -- عصير الليمون 200 مل
UPDATE "public"."inventory" SET brand = NULL, variety = 'مانجو', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '15b39feb-4b57-47bd-bddc-4d6e7784f7c5';  -- عصير المانجو 200 مل
UPDATE "public"."inventory" SET brand = NULL, variety = 'فواكه مشكلة', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'ae59f6a4-f54c-418e-8a3f-1fb4d1010ffa';  -- عصير فواكة المشكلة 200 مل
UPDATE "public"."inventory" SET brand = 'القصيم', variety = 'خلطة', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '7f52dd4e-6cab-4dc0-8c04-0d69b1bcf94e';  -- القصيم - خلطة القهوة - 250 جم
UPDATE "public"."inventory" SET brand = 'القصيم', variety = 'خلطة', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'd464b6d0-ae7d-4942-bc02-edc4f4047dad';  -- القصيم - خلطة القهوة - 500 جم
UPDATE "public"."inventory" SET brand = NULL, variety = 'برازيلي سانتوس محمص', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '9aac8984-96d7-4039-9783-15e7d0a80cf7';  -- بن برازيلي سانتوس محمص - 1 كيلو
UPDATE "public"."inventory" SET brand = NULL, variety = 'هرري محمص غامق', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '8c63fa4d-f4c8-4f7e-91a8-2dff8f8e0095';  -- بن هرري محمص غامق - 1 كجم
UPDATE "public"."inventory" SET brand = NULL, variety = 'هرري محمص وسط', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '51961a41-9f15-4654-a84d-e3ed79c42ec1';  -- بن هرري محمص وسط - 1 كجم
UPDATE "public"."inventory" SET brand = NULL, variety = 'هرري مطحون غامق', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '8d798c25-ea1f-4744-a217-02a3f424b404';  -- بن هرري مطحون غامق - 1 كجم
UPDATE "public"."inventory" SET brand = NULL, variety = 'أرابيكا حبوب', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '10941c76-2ce7-48d2-b965-e0b227e67691';  -- حبوب قهوة ارابيكا - 1 كجم
UPDATE "public"."inventory" SET brand = NULL, variety = 'فاخرة حبوب', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '7c77f671-399b-4bb5-9995-dd02c257e4c8';  -- حبوب قهوة فاخرة - 1 كيلو
UPDATE "public"."inventory" SET brand = NULL, variety = 'إثيوبي', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '1f4f7ea9-7c53-449b-abb0-dc4f955f0c18';  -- قهوة اثيوبي 907 جم
UPDATE "public"."inventory" SET brand = 'العمدة', variety = 'مخلوط', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'fe9aae4e-24cb-48fe-bf39-efc5dedf76f8';  -- قهوة العمدة مخلوط - 1 كيلو
UPDATE "public"."inventory" SET brand = NULL, variety = 'برازيلي مطحون غامق', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'a865b5f4-7d23-4669-b84a-6fd2f9349ae2';  -- قهوة برازيلي مطحون غامق - 1 كيلو
UPDATE "public"."inventory" SET brand = 'دانكن', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'b42d2360-78b5-48c2-9e0e-8ae5ee9756c2';  -- قهوة دانكن 453 جم
UPDATE "public"."inventory" SET brand = 'دانكن دونتس', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '4b7ab99c-89f5-4628-9a7f-66a1570e9425';  -- قهوة دانكن دونتس 40 اونص
UPDATE "public"."inventory" SET brand = 'دانكن دونتس', variety = 'مزيج القهوة', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '18724482-1167-4974-aa50-885c3e76f602';  -- قهوة دانكن دونتس مزيج القهوة 12 اونص
UPDATE "public"."inventory" SET brand = 'سعدي بيشة', variety = 'مطحون', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'b751c0db-e198-4c24-ab9c-e5093d5124d4';  -- قهوة سعدي بيشة مطحون - 1 كيلو
UPDATE "public"."inventory" SET brand = 'كيف الشيوخ', variety = 'عربي', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '067277ae-b194-497d-ab1b-32093ff0fedd';  -- قهوة عربي كيف الشيوخ
UPDATE "public"."inventory" SET brand = NULL, variety = 'كوستاريكي', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '718d4c7d-75fb-44ea-b3c5-2147cc3a447d';  -- قهوة كوستاريكي
UPDATE "public"."inventory" SET brand = 'كوفي هوليك', variety = 'إثيوبي', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '059eb2b5-a093-4f60-b5e1-47750b3e86fc';  -- قهوة كوفي هوليك اثيوبي 1 كجم
UPDATE "public"."inventory" SET brand = 'كوفي هوليك', variety = 'كولمبي', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'f779c4fb-9461-4278-b56f-1418f085337e';  -- قهوة كوفي هوليك كولمبي - 1 كجم
UPDATE "public"."inventory" SET brand = 'كوفي هوليك', variety = 'كولمبي', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'fd056e99-977d-4472-8ce0-6132326bbdf7';  -- قهوة كوفي هوليك كولمبي - 500 جم
UPDATE "public"."inventory" SET brand = NULL, variety = 'كولمبي', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '206db76d-3682-42ab-b60d-eb2cb1db0931';  -- قهوة كوليمبي 907 جم
UPDATE "public"."inventory" SET brand = 'لدن', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '7d414720-904f-416b-a88b-e7a3959bc5a1';  -- قهوة لدن 1 كجم
UPDATE "public"."inventory" SET brand = 'لدن', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '8ef94067-62f9-4c27-b070-8a97bec430e3';  -- قهوة لدن 3 كجم
UPDATE "public"."inventory" SET brand = 'لدن', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '21c9bfbf-3c8e-434d-9bb3-604ce89882b4';  -- قهوة لدن 500 حم
UPDATE "public"."inventory" SET brand = 'لولوة', variety = 'محمص مخلوط', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'df1dd665-3e35-4d90-bb5e-7d9a0df1a880';  -- قهوة لولوة محمص مخلوطة
UPDATE "public"."inventory" SET brand = 'محمد أفندي', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '18ac0cde-1185-46b2-9e16-dd7e723b0407';  -- قهوة محمد افندي 250 جم
UPDATE "public"."inventory" SET brand = 'محمصة الرياض', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'ed8bb260-d895-479a-b66a-bebd9e94dd27';  -- قهوة محمصة الرياض
UPDATE "public"."inventory" SET brand = 'هوليك', variety = 'إسبريسو', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '593f9814-6a70-4b79-b467-e5da0891bc72';  -- قهوة هوليك - اسبريسو
UPDATE "public"."inventory" SET brand = 'هيفاء', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '71633eca-d39e-43ff-84f6-7c39f2f8f99d';  -- قهوة هيفاء - 1 كجم
UPDATE "public"."inventory" SET brand = 'وزنة', variety = 'سعودية', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'c4d96f0d-8f24-4bcd-82b6-9d1d853cb8d6';  -- قهوة وزنة السعودية - 1 كيلو
UPDATE "public"."inventory" SET brand = 'وزنة', variety = 'كولمبي', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '9779c660-59c2-44b6-a4ab-068658a70b1b';  -- قهوة وزنة كولمبي 1 كجم
UPDATE "public"."inventory" SET brand = 'كوفيك', variety = 'حب', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '9571f224-7349-4509-bf88-1d5d1dab6ce8';  -- كوفيك - قهوة حب - 1 كجم
UPDATE "public"."inventory" SET brand = 'نسكافيه', variety = 'كلاسيك', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '629d125c-376a-48d6-a0a9-48e694c1e954';  -- نسكافي كلاسيك 100 جم
UPDATE "public"."inventory" SET brand = 'نسكافيه', variety = 'كلاسيك', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '7cff11f7-a09b-4cff-9404-b0baa0c91ed0';  -- نسكافي كلاسيك 190 جم
UPDATE "public"."inventory" SET brand = 'نسكافيه', variety = '3×1', packaging_size = 25, packaging_size_unit = 'ظرف'
  WHERE "id" = 'e77f5ac9-8c0c-42d4-99ae-d443d8a80a63';  -- نسكافيه 3*1 - شد 24 عدد 25 ظرف
UPDATE "public"."inventory" SET brand = 'الضيف', variety = 'منوع', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '7a1f2273-fae2-4686-a8ee-b3494e2bd579';  -- بسبوسة منوع 350 جم - الضيف
UPDATE "public"."inventory" SET brand = NULL, variety = 'شوفان متنوع', packaging_size = 5, packaging_size_unit = 'حبة'
  WHERE "id" = '4e229e33-a70a-4761-a4a6-7fda764d1251';  -- بسكوت شوفان 210 جم شد 5 - متنوع
UPDATE "public"."inventory" SET brand = 'الضيف', variety = 'بالسمسم والطحينة', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '3088fa1b-b331-45a4-8c45-0317ba615a39';  -- تمرية بالسمسم والطحينة - الضيف
UPDATE "public"."inventory" SET brand = NULL, variety = 'تفاح', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'ba27533e-b1f3-4e82-8d0c-4157a7e6e973';  -- فطيرة التفاح 70 جم
UPDATE "public"."inventory" SET brand = NULL, variety = 'جبنة', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '8d14cf26-cac2-4ac4-acdb-03137f3e7253';  -- فطيرة الجبنة 70 جم
UPDATE "public"."inventory" SET brand = NULL, variety = 'جبنة', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'bcfd44dd-b3a8-42a9-93e6-c169da8c09bc';  -- كرواسان الجبنة 60 جم
UPDATE "public"."inventory" SET brand = NULL, variety = 'زبدة', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '131cee3b-f20a-4dfc-89f1-7183b1f00fae';  -- كرواسان الزبدة 85 جم
UPDATE "public"."inventory" SET brand = NULL, variety = 'سمسم ميني طرية', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'd5394305-28e8-4efd-b986-3fef83d6e454';  -- كعك السمسم ميني - طرية
UPDATE "public"."inventory" SET brand = NULL, variety = 'حساوي', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '08fb04c7-24c8-4776-9c67-2905d8537fd1';  -- كوكيز حساوي
UPDATE "public"."inventory" SET brand = 'انيشن', variety = 'مقاس 1×2', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '68b1e61a-1bda-4303-a95d-e81c6fb4ca80';  -- فلتر قهوة انيشن 1*2
UPDATE "public"."inventory" SET brand = 'انيشن', variety = 'مقاس 1×4', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '6f3482b6-a451-46b4-a8fe-efa03f7a4d15';  -- فلتر قهوة انيشن 1*4
UPDATE "public"."inventory" SET brand = NULL, variety = NULL, packaging_size = 100, packaging_size_unit = 'حبة'
  WHERE "id" = '770f3b45-25b7-4d21-bea0-ae8075af8471';  -- فلتر قهوة بن - 100 حبة   [العلامة مؤجَّلة]
UPDATE "public"."inventory" SET brand = 'ماليتا', variety = 'صغير', packaging_size = 80, packaging_size_unit = 'حبة'
  WHERE "id" = 'a037f605-0215-4199-bfd3-5c051f61c3c6';  -- فلتر قهوة ماليتا صغير شد 1*80 شد 9
UPDATE "public"."inventory" SET brand = 'ماليتا', variety = 'وسط', packaging_size = 40, packaging_size_unit = 'حبة'
  WHERE "id" = '379a65b5-c9ae-4564-88cc-b2fe808edc3f';  -- فلتر قهوة ماليتا وسط شد 1*40 شد 18
UPDATE "public"."inventory" SET brand = 'مستر كوفي', variety = NULL, packaging_size = 100, packaging_size_unit = 'حبة'
  WHERE "id" = '20466342-7970-4c33-890d-ede48c5d9beb';  -- فلتر قهوة مستر كوفي - 100 حبة
UPDATE "public"."inventory" SET brand = 'مستر كوفي', variety = NULL, packaging_size = 50, packaging_size_unit = 'حبة'
  WHERE "id" = '56ec7402-412d-4adc-8c86-0185dba0ce6b';  -- فلتر قهوة مستر كوفي - 50 حبة
UPDATE "public"."inventory" SET brand = 'كوفي ميت', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '6d693601-9005-42d5-b4b9-c9690a7e89f5';  -- كوفي ميت - 400 جم
UPDATE "public"."inventory" SET brand = NULL, variety = 'مع الحليب', packaging_size = 10, packaging_size_unit = 'كيس'
  WHERE "id" = '4803c079-fb92-42cc-8df5-bcd3e5d63597';  -- مبيض قهوة مع الحليب شد 10*500 جم
UPDATE "public"."inventory" SET brand = NULL, variety = 'خشب', packaging_size = 250, packaging_size_unit = 'حبة'
  WHERE "id" = 'f51a187d-5b5e-4643-9cf4-29bb94729773';  -- محرك خشب - 250 حبة
UPDATE "public"."inventory" SET brand = NULL, variety = 'خشب مغلف', packaging_size = 500, packaging_size_unit = 'حبة'
  WHERE "id" = '7de5724f-9732-4c2c-a100-17810f06cf04';  -- محرك خشب مغلف 4M شد 500
UPDATE "public"."inventory" SET brand = 'أفران الحطب', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '06c8cd1b-df43-4e86-b271-f9ac9ce19403';  -- معمول - افران الحطب
UPDATE "public"."inventory" SET brand = 'الضيف', variety = 'تمر', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '22111a65-0779-4d01-bddc-0bbf5ea3ec6c';  -- معمول التمر - الضيف
UPDATE "public"."inventory" SET brand = 'ترفة', variety = 'تمر أبيض', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '92ad19c9-ee09-4c17-b732-bd5afec8931e';  -- معمول تمر ابيض - ترفة
UPDATE "public"."inventory" SET brand = 'الضيف', variety = 'تمر بر', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '9646b797-5bcf-422c-945a-aedc80e01823';  -- معمول تمر بر - الضيف
UPDATE "public"."inventory" SET brand = 'الضيف', variety = 'توفي', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'a0c7fae3-48c5-4e0c-ac51-9243ff9f4dc6';  -- معمول توفي - الضيف
UPDATE "public"."inventory" SET brand = 'ترفة', variety = 'توفي أبيض', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '1eaa7bf1-cfb3-4995-879f-a7b146031332';  -- معمول توفي ابيض - ترفة
UPDATE "public"."inventory" SET brand = 'رغد', variety = 'منوع', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '3a6322bb-dac9-4656-bd0a-19f208d620b2';  -- معمول رغد منوع
UPDATE "public"."inventory" SET brand = 'أطياف', variety = 'مشكل ديلوكس', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '42cdcd7a-9ba2-404d-9cf6-fb23198ee21e';  -- أطياف - مكسرات مشكل ديلوكس - 1 كجم
UPDATE "public"."inventory" SET brand = 'باجة', variety = 'مشكل فاخر', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'd4ac2073-eb53-49fc-bb96-6383c746889d';  -- باجة - مشكل مكسرات فاخر 15 جم
UPDATE "public"."inventory" SET brand = 'باجة', variety = 'VIP', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'ed35e70c-be6c-43a6-95c5-13df46bdc6a3';  -- باجة - مكسرات VIP - وزن 1 كجم
UPDATE "public"."inventory" SET brand = NULL, variety = 'مشكلة', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'e34ab90b-288c-4b34-9b94-07f7e15e92fe';  -- مكسرات مشكلة - ا كجم
UPDATE "public"."inventory" SET brand = 'المنهل', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'b37d0bd1-faec-45bb-b128-149c68dd560b';  -- قاروة مياة المنهل
UPDATE "public"."inventory" SET brand = 'صحة', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '70323742-d4f0-463c-9107-27bad2201793';  -- قاروة مياة صحة 5 جالون
UPDATE "public"."inventory" SET brand = 'بيريه', variety = NULL, packaging_size = 24, packaging_size_unit = 'حبة'
  WHERE "id" = '19daf066-8859-46ab-8d0a-6fb86895fa0e';  -- مياة بيريه - شد 24 حبة 330 مل
UPDATE "public"."inventory" SET brand = 'نوفا', variety = NULL, packaging_size = 12, packaging_size_unit = 'حبة'
  WHERE "id" = 'f431b7ee-ad1a-4520-9766-0c6f78bcb88d';  -- مياة نوفا  1.50 لتر - 12 حبة
UPDATE "public"."inventory" SET brand = 'نوفا', variety = NULL, packaging_size = 24, packaging_size_unit = 'حبة'
  WHERE "id" = '2c9d8343-d78f-4299-a063-d2248ce8dcb8';  -- مياة نوفا 200 مل - 24 حبة
UPDATE "public"."inventory" SET brand = 'نوفا', variety = NULL, packaging_size = 40, packaging_size_unit = 'حبة'
  WHERE "id" = 'c2ef248d-18f3-4a2d-89e3-69b9ee37405b';  -- مياة نوفا 330 مل - 40 حبة
UPDATE "public"."inventory" SET brand = 'نوفا', variety = 'زجاج', packaging_size = 24, packaging_size_unit = 'حبة'
  WHERE "id" = 'a94d2d9a-b6b3-4529-836e-598d8a7e9192';  -- مياة نوفا زجاج 250 مل - 24 حبة
UPDATE "public"."inventory" SET brand = 'نوفا', variety = 'سبارك فوار', packaging_size = 24, packaging_size_unit = 'حبة'
  WHERE "id" = '770e3420-de73-46d2-979f-1b8bc2026040';  -- مياة نوفا سبارك فوار 250 مل - 24 حبة
UPDATE "public"."inventory" SET brand = 'أبو دلة', variety = 'خضراء مطحون', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'a29f3438-681a-40a0-be5d-aa0fe9881ae1';  -- هيل ابو دلة خضراء - مطحون 250جم
UPDATE "public"."inventory" SET brand = 'أبو دلة', variety = 'خضراء سيلفر مطحون', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'cc1eabf9-ce67-4a6a-8972-d3d74747b52c';  -- هيل ابو دلة خضراء سيلفر - مطحون
UPDATE "public"."inventory" SET brand = 'الدلة الذهبية', variety = 'الماز', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '9f881946-a17d-4d6e-a1be-0e80e308d497';  -- هيل الدلة الذهبية الماز
UPDATE "public"."inventory" SET brand = 'الدلة الذهبية', variety = 'الماز', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'c2a1cac9-2250-4a70-bed0-1467e0331358';  -- هيل الدلة الذهبية الماز 5 كجم
UPDATE "public"."inventory" SET brand = 'الدلة الذهبية', variety = 'الماز حب', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '62a4dc82-16d4-499c-a461-f54ef435e5ca';  -- هيل الدلة الذهبية الماز حب - 500 جرام
UPDATE "public"."inventory" SET brand = 'الدلة الذهبية', variety = 'مطحون', packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = 'f424b17b-241f-4cae-94ba-38e7e4f51a57';  -- هيل الدلة الذهبية مطحون - 250جم
UPDATE "public"."inventory" SET brand = 'ليز', variety = 'متنوع', packaging_size = 6, packaging_size_unit = 'حبة'
  WHERE "id" = 'cac4b544-1722-43f3-a7fa-32ce4f98143a';  -- شيبسي ليز 6 حبة *21 جم - متنوع
UPDATE "public"."inventory" SET brand = 'نسبرسو', variety = NULL, packaging_size = NULL, packaging_size_unit = NULL
  WHERE "id" = '0d0fcc7d-400e-4911-a914-784772f2d7d4';  -- كبسولات نسبرسو

@isTest
private class DynamicDocumentRendererTest {

    @isTest
    static void testRenderDocument_BlankJson() {
        Test.startTest();
        String result = DynamicDocumentRenderer.renderDocument('', null, 'Account');
        Test.stopTest();
        System.assertEquals('', result, 'Blank JSON should return empty string');
    }

    @isTest
    static void testRenderDocument_NullJson() {
        Test.startTest();
        String result = DynamicDocumentRenderer.renderDocument(null, null, 'Account');
        Test.stopTest();
        System.assertEquals('', result, 'Null JSON should return empty string');
    }

    @isTest
    static void testRenderDocument_MinimalTemplate() {
        String templateJson = '{"styles":{"fontFamily":"Arial","fontSize":"12px","primaryColor":"#333"}}';
        Test.startTest();
        String result = DynamicDocumentRenderer.renderDocument(templateJson, null, 'Account');
        Test.stopTest();
        System.assert(result.contains('font-family:Arial'), 'Should contain font family');
    }

    @isTest
    static void testRenderDocument_WithHeaderAndFooter() {
        String templateJson = JSON.serialize(new Map<String, Object>{
            'header' => new Map<String, Object>{
                'content' => 'Header Text',
                'showLogo' => false
            },
            'footer' => new Map<String, Object>{
                'content' => 'Footer Text',
                'showPageNumbers' => true,
                'pageNumberPosition' => 'center'
            },
            'styles' => new Map<String, Object>{
                'fontFamily' => 'Helvetica',
                'fontSize' => '14px',
                'primaryColor' => '#000'
            }
        });

        Test.startTest();
        String result = DynamicDocumentRenderer.renderDocument(templateJson, null, 'Account');
        Test.stopTest();
        System.assert(result.contains('Header Text'), 'Should contain header text');
        System.assert(result.contains('Footer Text'), 'Should contain footer text');
        System.assert(result.contains('pagenumber'), 'Should contain page number span');
    }

    @isTest
    static void testRenderDocument_WithRecord() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        String templateJson = JSON.serialize(new Map<String, Object>{
            'header' => new Map<String, Object>{
                'content' => 'Account: {!Name}'
            },
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'content',
                    'content' => 'Name is {!Name}'
                }
            },
            'footer' => new Map<String, Object>{
                'content' => 'Generated on {!TODAY}'
            }
        });

        Test.startTest();
        String result = DynamicDocumentRenderer.renderDocument(templateJson, acc.Id, 'Account');
        Test.stopTest();
        System.assert(result.contains('Test Account'), 'Should resolve merge field to account name');
    }

    @isTest
    static void testRenderDocument_SeparatorSection() {
        String templateJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'separator',
                    'style' => 'dashed'
                }
            }
        });

        Test.startTest();
        String result = DynamicDocumentRenderer.renderDocument(templateJson, null, 'Account');
        Test.stopTest();
        System.assert(result.contains('<hr'), 'Should contain hr tag');
        System.assert(result.contains('dashed'), 'Should contain dashed style');
    }

    @isTest
    static void testRenderDocument_HeadingSection() {
        String templateJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'heading',
                    'content' => 'Test Heading',
                    'level' => '3',
                    'textAlign' => 'center',
                    'textColor' => '#ff0000'
                }
            }
        });

        Test.startTest();
        String result = DynamicDocumentRenderer.renderDocument(templateJson, null, 'Account');
        Test.stopTest();
        System.assert(result.contains('<h3'), 'Should contain h3 tag');
        System.assert(result.contains('Test Heading'), 'Should contain heading text');
    }

    @isTest
    static void testRenderDocument_PageBreakSection() {
        String templateJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'pageBreak'
                }
            }
        });

        Test.startTest();
        String result = DynamicDocumentRenderer.renderDocument(templateJson, null, 'Account');
        Test.stopTest();
        System.assert(result.contains('page-break-after'), 'Should contain page break');
    }

    @isTest
    static void testRenderDocument_ImageSection() {
        String templateJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'image',
                    'imageUrl' => 'https://example.com/logo.png',
                    'textAlign' => 'center',
                    'imageMaxWidth' => '200px',
                    'imageCaption' => 'Company Logo'
                }
            }
        });

        Test.startTest();
        String result = DynamicDocumentRenderer.renderDocument(templateJson, null, 'Account');
        Test.stopTest();
        System.assert(result.contains('https://example.com/logo.png'), 'Should contain image URL');
        System.assert(result.contains('Company Logo'), 'Should contain caption');
    }

    @isTest
    static void testRenderDocument_ImageSection_EmptyUrl() {
        String templateJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'image',
                    'imageUrl' => ''
                }
            }
        });

        Test.startTest();
        String result = DynamicDocumentRenderer.renderDocument(templateJson, null, 'Account');
        Test.stopTest();
        System.assert(!result.contains('<img'), 'Should not contain img tag when no URL');
    }

    @isTest
    static void testRenderDocument_TableSection_MissingConfig() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        String templateJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'table',
                    'title' => 'Missing Table'
                }
            }
        });

        Test.startTest();
        String result = DynamicDocumentRenderer.renderDocument(templateJson, acc.Id, 'Account');
        Test.stopTest();
        System.assert(result.contains('missing configuration'), 'Should show missing config message');
    }

    @isTest
    static void testRenderDocument_TableSection_WithData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        Contact con = new Contact(FirstName = 'John', LastName = 'Doe', AccountId = acc.Id);
        insert con;

        String templateJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'table',
                    'title' => 'Contacts',
                    'childObject' => 'Contact',
                    'relationshipField' => 'AccountId',
                    'columns' => new List<Object>{
                        new Map<String, Object>{ 'label' => 'Last Name', 'field' => 'LastName' }
                    },
                    'orderBy' => 'LastName',
                    'maxRows' => 10,
                    'showRowNumbers' => true,
                    'alternateRowColors' => true,
                    'alternateRowBackground' => '#f0f0f0'
                }
            }
        });

        Test.startTest();
        String result = DynamicDocumentRenderer.renderDocument(templateJson, acc.Id, 'Account');
        Test.stopTest();
        System.assert(result.contains('Contacts'), 'Should contain table title');
        System.assert(result.contains('Doe'), 'Should contain contact last name');
    }

    @isTest
    static void testRenderDocument_FieldGridSection() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        String templateJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'fieldGrid',
                    'gridColumns' => 2,
                    'fields' => new List<Object>{
                        new Map<String, Object>{ 'label' => 'Name', 'field' => 'Name' },
                        new Map<String, Object>{ 'label' => 'Id', 'field' => 'Id' },
                        new Map<String, Object>{ 'label' => 'Extra', 'field' => 'Name' }
                    }
                }
            }
        });

        Test.startTest();
        String result = DynamicDocumentRenderer.renderDocument(templateJson, acc.Id, 'Account');
        Test.stopTest();
        System.assert(result.contains('Test Account'), 'Should contain field grid values');
    }

    @isTest
    static void testRenderDocument_ThreeColumnHeader() {
        String templateJson = JSON.serialize(new Map<String, Object>{
            'header' => new Map<String, Object>{
                'left' => new Map<String, Object>{ 'type' => 'text', 'content' => 'Left Content' },
                'center' => new Map<String, Object>{ 'type' => 'none' },
                'right' => new Map<String, Object>{ 'type' => 'image', 'logoUrl' => 'https://example.com/logo.png' },
                'fontSize' => '16px',
                'bold' => true,
                'textColor' => '#000'
            }
        });

        Test.startTest();
        String result = DynamicDocumentRenderer.renderDocument(templateJson, null, 'Account');
        Test.stopTest();
        System.assert(result.contains('Left Content'), 'Should contain left column text');
        System.assert(result.contains('https://example.com/logo.png'), 'Should contain logo URL');
    }

    @isTest
    static void testRenderDocument_LegacyHeaderWithLogo() {
        String templateJson = JSON.serialize(new Map<String, Object>{
            'header' => new Map<String, Object>{
                'content' => 'Legacy Header',
                'showLogo' => true,
                'logoUrl' => 'https://example.com/legacy-logo.png',
                'logoPosition' => 'center'
            }
        });

        Test.startTest();
        String result = DynamicDocumentRenderer.renderDocument(templateJson, null, 'Account');
        Test.stopTest();
        System.assert(result.contains('Legacy Header'), 'Should contain legacy header content');
        System.assert(result.contains('legacy-logo.png'), 'Should contain logo URL');
    }

    @isTest
    static void testRenderDocument_ContentSectionStyles() {
        String templateJson = JSON.serialize(new Map<String, Object>{
            'sections' => new List<Object>{
                new Map<String, Object>{
                    'type' => 'content',
                    'content' => 'Styled Content',
                    'backgroundColor' => '#ffffff',
                    'padding' => '16px',
                    'textAlign' => 'center',
                    'fontSize' => '18px',
                    'bold' => true,
                    'textColor' => '#0000ff'
                }
            }
        });

        Test.startTest();
        String result = DynamicDocumentRenderer.renderDocument(templateJson, null, 'Account');
        Test.stopTest();
        System.assert(result.contains('Styled Content'), 'Should contain content text');
        System.assert(result.contains('font-weight:bold'), 'Should contain bold styling');
    }

    @isTest
    static void testStringBuilder() {
        DynamicDocumentRenderer.StringBuilder sb = new DynamicDocumentRenderer.StringBuilder();
        sb.append('Hello');
        sb.append(' ');
        sb.append('World');
        sb.append(null);
        System.assertEquals('Hello World', sb.toString());
    }
}